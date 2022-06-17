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

    grep -v "^builder" /etc/passwd > /tmp/passwd
    echo "builder:x:${user_id}:${group_id}::/home/builder:/bin/bash" >> /tmp/passwd
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
    # Always create a writable copy of the source repo
    tmp_src="$(mktemp -d)"
    cp -a /src "${tmp_src}/os"

    # Either use the COSA_DIR prepared for us or create a temporary cosa workdir
    cosa_dir="${COSA_DIR:-$(mktemp -d)}"
    echo "Using $cosa_dir for build"
    cd "$cosa_dir"

    # Setup source tree
    cosa init --transient "${tmp_src}/os"
    # Select RHEL os CentOS Stream version
    # This must be defined for each test job entry point
    if [[ -z ${RHELVER+x} ]]; then
        echo "No RHEL or CentOS Stream version selected to build RHCOS/SCOS"
        exit 1
    fi
    pushd src/config
    ./select_version.sh "${RHELVER}"
    popd
}

# Do a cosa build & cosa build-extensions only.
# This is called both as part of the build phase and test phase in Prow thus we
# can not do any kola testing in this function.
# We do not build the QEMU image here as we don't need it in the pure container
# test case.
cosa_build() {
    # Grab the raw value of `mutate-os-release` and use sed to convert the value
    # to X-Y format
    ocpver=$(rpm-ostree compose tree --print-only src/config/manifest.yaml | jq -r '.["mutate-os-release"]')
    ocpver_mut=$(rpm-ostree compose tree --print-only src/config/manifest.yaml | jq -r '.["mutate-os-release"]' | sed 's|\.|-|')

    # Temporary workaround until we publish builds for other versions
    if [[ "${RHELVER}" == "rhel-8.6" ]]; then
        prev_build_url=${REDIRECTOR_URL}/rhcos-${ocpver}/
        # Fetch the previous build
        cosa buildfetch --url="${prev_build_url}"
    fi

    # Fetch the repos corresponding to the release we are building
    # Temporarily double checked until we have uniformity for all RHEL and
    # CentOS versions
    if [[ "${RHELVER}" == "rhel-8.6" ]]; then
        rhelver=$(rpm-ostree compose tree --print-only src/config/manifest.yaml | jq -r '.["automatic-version-prefix"]' | cut -f2 -d.)
        curl -L "http://base-${ocpver_mut}-rhel${rhelver}.ocp.svc.cluster.local" -o "src/config/ocp.repo"
    elif [[ "${RHELVER}" == "rhel-9.0" ]]; then
        # Temporary workaround until we have all packages for RHCOS 9
        curl -L "http://base-${ocpver_mut}-rhel86.ocp.svc.cluster.local" -o "src/config/ocp.repo"
        curl -L "http://base-${ocpver_mut}-rhel90.ocp.svc.cluster.local" -o "src/config/ocp.repo"
    elif [[ "${RHELVER}" == "c9s" ]]; then
        sed "s|file:///tmp|file://${PWD}/src/config/rpm-gpg|" "src/config/repos/c9s.repo" > "src/config/c9s.repo"
        # Temporary workaround until we have all packages for SCOS
        curl -L "http://base-${ocpver_mut}-rhel86.ocp.svc.cluster.local" -o "src/config/tmp.repo"
        awk '/rhel-8-server-ose/,/^$/' "src/config/tmp.repo" > "src/config/ocp.repo"
        echo "includepkgs=cri-o,cri-tools,openshift-clients,openshift-hyperkube" >> "src/config/ocp.repo"
        rm "src/config/tmp.repo"
    fi

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
    if [[ "${#}" -ne 1 ]]; then
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
        "build")
            cosa_init
            cosa_build
            ;;
        "rhcos-cosa-prow-pr-ci" | "rhcos-86-build-test-qemu")
            RHELVER="rhel-8.6"
            setup_user
            cosa_init
            cosa_build
            kola_test_qemu
            ;;
        "rhcos-86-build-test-metal")
            RHELVER="rhel-8.6"
            setup_user
            cosa_init
            cosa_build
            kola_test_metal
            ;;
        "rhcos-90-build-test-qemu")
            RHELVER="rhel-9.0"
            setup_user
            cosa_init
            cosa_build
            kola_test_qemu
            ;;
        "rhcos-90-build-test-metal" )
            RHELVER="rhel-9.0"
            setup_user
            cosa_init
            cosa_build
            kola_test_metal
            ;;
        "scos-9-build-test-qemu")
            RHELVER="c9s"
            setup_user
            cosa_init
            cosa_build
            kola_test_qemu
            ;;
        "scos-9-build-test-metal" )
            RHELVER="c9s"
            setup_user
            cosa_init
            cosa_build
            kola_test_metal
            ;;
        "explicitely-disabled-test")
            echo "Disabled tests"
            exit 0
            ;;
        *)
            echo "Unknown test name"
            exit 1
            ;;
    esac
}

main "${@}"

