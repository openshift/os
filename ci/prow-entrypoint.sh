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

cosa_init() {
    # Always create a writable copy of the source repo
    tmp_src="$(mktemp -d)"
    cp -a /src "${tmp_src}/os"

    # Either use the COSA_DIR prepared for us or create a temporary cosa workdir
    cosa_dir="${COSA_DIR:-$(mktemp -d)}"
    echo "Using $cosa_dir for build"
    cd "$cosa_dir"

    # Setup source tree
    cosa init --transient "${tmp_src}/os"
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
    prev_build_url=${REDIRECTOR_URL}/rhcos-${ocpver}/
    # Fetch the previous build
    cosa buildfetch --url="${prev_build_url}"

    # Fetch the repos corresponding to the release we are building
    rhelver=$(rpm-ostree compose tree --print-only src/config/manifest.yaml | jq -r '.["automatic-version-prefix"]' | cut -f2 -d.)
    id
    whoami
    ls -alh "src/config/"
    curl -L "http://base-${ocpver_mut}-rhel${rhelver}.ocp.svc.cluster.local" -o "src/config/ocp.repo"

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
        "rhcos-86-build-test-qemu")
            setup_user
            cosa_init
            cosa_build
            kola_test_qemu
            ;;
        "rhcos-86-build-test-metal")
            setup_user
            cosa_init
            cosa_build
            kola_test_metal
            ;;
        "build-test-qemu-kola-upgrade" | "build-test-qemu-kola-metal" | "rhcos-90-build-test-qemu" | "rhcos-90-build-test-metal" | "scos-9-build-test-qemu" | "scos-9-build-test-metal")
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

