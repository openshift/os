#!/bin/bash
set -xeuo pipefail

# Main script acting as entrypoint for all Prow jobs building RHCOS images

# Global variables
REDIRECTOR_URL="https://rhcos-redirector.apps.art.xq1c.p1.openshiftapps.com/art/storage/releases/"

# This function is used to update the /etc/passwd file within the COSA container
# at test-time. The need for this comes from the fact that OpenShift will run a
# container with a randomized user ID by default to enhance security. Because
# COSA runs with an unprivileged user ("builder") instead of (container) root,
# this presents special challenges for file and disk permissions. This particular
# pattern was inspired by:
# - https://cloud.redhat.com/blog/jupyter-on-openshift-part-6-running-as-an-assigned-user-id
# - https://cloud.redhat.com/blog/a-guide-to-openshift-and-uids
setup_user() {
    user_id="$(id -u)"
    group_id="$(id -g)"
    # create a homedir we're sure our UID will have access to
    homedir=$(mktemp -d -p /var/tmp)

    grep -v "^prowbuilder" /etc/passwd > /tmp/passwd
    echo "prowbuilder:x:${user_id}:${group_id}::${homedir}:/bin/bash" >> /tmp/passwd
    cat /tmp/passwd > /etc/passwd
    rm /tmp/passwd

    # Not strictly required, but nice for debugging.
    id
    whoami
}

# Setup a new build directory with COSA init, selecting the version of RHEL or
# CentOS Stream that we want as a basis for RHCOS/SCOS.
cosa_init() {
    if test -d builds; then
        echo "Already in an initialized cosa dir"
        return
    fi

    if [[ ${#} -ne 1 ]]; then
        echo "This should have been called with a single 'variant' argument"
        exit 1
    fi
    local -r variant="${1}"
    echo "Using variant: ${variant}"

    # Always create a writable copy of the source repo
    tmp_src="$(mktemp -d)"
    cp -a /src "${tmp_src}/os"

    # Either use the COSA_DIR prepared for us or create a temporary cosa workdir
    cosa_dir="${COSA_DIR:-$(mktemp -d)}"
    echo "Using $cosa_dir for build"
    cd "$cosa_dir"

    # Setup source tree
    cosa init --transient --variant "${variant}" "${tmp_src}/os"
}

# Initialize the .repo files
prepare_repos() {
    local manifest="src/config/manifest.yaml"
    if [[ -f "src/config.json" ]]; then
        variant="$(jq --raw-output '."coreos-assembler.config-variant"' 'src/config.json')"
        manifest="src/config/manifest-${variant}.yaml"
    fi
    # Grab the raw value of `mutate-os-release` and use sed to convert the value
    # to X-Y format
    ocpver=$(rpm-ostree compose tree --print-only "${manifest}" | jq -r '.["mutate-os-release"]')
    ocpver_mut=$(rpm-ostree compose tree --print-only "${manifest}" | jq -r '.["mutate-os-release"]' | sed 's|\.|-|')

    # Figure out which version we're building
    rhelver=$(rpm-ostree compose tree --print-only "${manifest}" | jq -r '.["automatic-version-prefix"]' | cut -f2 -d.)

    # Temporary workaround until we publish builds for other versions
    if [[ "${rhelver}" == "86" ]]; then
        prev_build_url="${REDIRECTOR_URL}/rhcos-${ocpver}/"
        # Fetch the previous build
        cosa buildfetch --url="${prev_build_url}"
    fi

    # Fetch the repos corresponding to the release we are building
    if [[ "${rhelver}" == "86" ]]; then
        curl --fail -L "http://base-${ocpver_mut}-rhel${rhelver}.ocp.svc.cluster.local" -o "src/config/ocp.repo"
    elif [[ "${rhelver}" == "90" ]]; then
        curl --fail -L "http://base-${ocpver_mut}-rhel${rhelver}.ocp.svc.cluster.local" -o "src/config/ocp.repo"

        # Temporary workaround until we have all packages for RHCOS 9
        curl --fail -L "http://base-${ocpver_mut}-rhel86.ocp.svc.cluster.local" -o "src/config/tmp.repo"
        awk '/rhel-8-server-ose/,/^$/' "src/config/tmp.repo" > "src/config/ocp86.repo"
        echo "includepkgs=skopeo" >> "src/config/ocp86.repo"
        rm "src/config/tmp.repo"
    else
        # Assume C9S/SCOS if the version does not match known values for RHEL
        # Temporary workaround until we have all packages for SCOS
        curl --fail -L "http://base-${ocpver_mut}-rhel90.ocp.svc.cluster.local" -o "src/config/tmp.repo"
        awk '/rhel-9-server-ose/,/^$/' "src/config/tmp.repo" > "src/config/ocp90.repo"
        echo "includepkgs=openshift-clients,openshift-hyperkube" >> "src/config/ocp90.repo"
        rm "src/config/tmp.repo"
    fi
}

# Do a cosa build & cosa build-extensions only.
# This is called both as part of the build phase and test phase in Prow thus we
# can not do any kola testing in this function.
# We do not build the QEMU image here as we don't need it in the pure container
# test case.
cosa_build() {
    prepare_repos
    # Fetch packages
    cosa fetch
    # Only build the ostree image by default
    cosa build ostree
    # Build extensions
    cosa buildextend-extensions
}

# Build QEMU image and run all kola tests
kola_test_qemu() {
    cosa buildextend-qemu
    cosa kola --basic-qemu-scenarios
    kola run-upgrade -b rhcos -v --find-parent-image --qemu-image-dir tmp/ --output-dir tmp/kola-upgrade
    cosa kola run --parallel 2
}

# Build metal, metal4k & live images and run kola tests
kola_test_metal() {
    # Build metal + installer now so we can test them
    cosa buildextend-metal
    cosa buildextend-metal4k
    cosa buildextend-live

    # Compress the metal and metal4k images now so we're testing
    # installs with the image format we ship
    cosa compress --artifact=metal --artifact=metal4k

    # Run all testiso scenarios on metal artifact
    kola testiso -S --scenarios pxe-install,pxe-offline-install,iso-install,iso-offline-install,iso-live-login,iso-as-disk,miniso-install --output-dir tmp/kola-metal

    # Run only the iso-install scenario to sanity-check the metal4k media
    kola testiso -S --qemu-native-4k --qemu-multipath --scenarios iso-install --output-dir tmp/kola-metal4k

    # Run some uefi & secure boot tests
    if [[ "$(uname -i)" == "x86_64" ]] || [[ "$(uname -i)" == "aarch64" ]]; then
        mkdir -p tmp/kola-uefi
        kola testiso -S --qemu-firmware uefi --scenarios iso-live-login,iso-as-disk --output-dir tmp/kola-uefi/insecure
        if [[ "$(uname -i)" == "x86_64" ]]; then
            kola testiso -S --qemu-firmware uefi-secure --scenarios iso-live-login,iso-as-disk --output-dir tmp/kola-uefi/secure
        fi
    fi
}

# Ensure that we can create all platform images for COSA CI
cosa_buildextend_all() {
    cosa buildextend-aliyun
    cosa buildextend-aws
    cosa buildextend-azure
    cosa buildextend-azurestack
    cosa buildextend-dasd
    cosa buildextend-gcp
    cosa buildextend-ibmcloud
    cosa buildextend-kubevirt
    cosa buildextend-live
    cosa buildextend-metal
    cosa buildextend-metal4k
    cosa buildextend-nutanix
    cosa buildextend-openstack
    cosa buildextend-powervs
    cosa buildextend-vmware

    # Will be done in another step
    # cosa buildextend-qemu

    # Currently not available for RHCOS
    # cosa buildextend-digitalocean
    # cosa buildextend-exoscale
    # cosa buildextend-virtualbox
    # cosa buildextend-vultr
}

# Basic syntaxt validation for manifests
validate() {
    # Create a temporary copy
    workdir="$(mktemp -d)"
    echo "Using $workdir as working directory"

    # Figure out if we are running from the COSA image or directly from the Prow src image
    if [[ -d /src/github.com/openshift/os ]]; then
        cd "$workdir"
        git clone /src/github.com/openshift/os os
    elif [[ -d ./.git ]]; then
        srcdir="${PWD}"
        cd "$workdir"
        git clone "${srcdir}" os
    else
        echo "Could not found source directory"
        exit 1
    fi
    cd os

    # First ensure submodules are initialized
    git submodule update --init --recursive
    # Basic syntax check
    ./fedora-coreos-config/ci/validate
}

main () {
    if [[ "${#}" -lt 1 ]]; then
        echo "This script is expected to be called by Prow with the name of the build phase or test to run"
        exit 1
    fi

    # Record information about cosa + rpm-ostree
    if [[ -d /cosa ]]; then
        jq . < /cosa/coreos-assembler-git.json
    fi
    if [[ $(command -v rpm-ostree) ]]; then
        rpm-ostree --version
    fi

    case "${1}" in
        "validate")
            validate
            ;;
        "init")
            cosa_init "$2"
            prepare_repos
            ;;
        "build" | "init-and-build-default")  # TODO: change prow job to use init-and-build-default
            cosa_init "rhel-coreos-8"
            cosa_build
            ;;
        "rhcos-cosa-prow-pr-ci")
            setup_user
            cosa_init "rhel-coreos-8"
            cosa_build
            kola_test_qemu
            ;;
        "rhcos-86-build-test-qemu")
            setup_user
            cosa_init "rhel-coreos-8"
            cosa_build
            kola_test_qemu
            ;;
        "rhcos-86-build-test-metal")
            setup_user
            cosa_init "rhel-coreos-8"
            cosa_build
            kola_test_metal
            ;;
        "rhcos-90-build-test-qemu")
            setup_user
            cosa_init "rhel-coreos-9"
            cosa_build
            # Temporarily disabled until all tests pass
            # kola_test_qemu
            ;;
        "rhcos-90-build-test-metal" )
            setup_user
            cosa_init "rhel-coreos-9"
            cosa_build
            # Temporarily disabled until all tests pass
            # kola_test_metal
            ;;
        "scos-9-build-test-qemu")
            setup_user
            cosa_init "scos"
            cosa_build
            kola_test_qemu
            ;;
        "scos-9-build-test-metal" )
            setup_user
            cosa_init "scos"
            cosa_build
            kola_test_metal
            ;;
        *)
            # This case ensures that we exhaustively list the tests that should
            # pass for a PR. To add a new test in openshift/os:
            # 1. Add a new test case here that does nothing and get it merged
            # 2. Add a new test job in openshift/release that calls this test
            # 3. Update your test here and debug it with the CI in the PR
            echo "Unknown test name"
            exit 1
            ;;
    esac
}

main "${@}"

