#!/bin/bash
set -xeuo pipefail
# This script is called via build-test-qemu.sh which is the main Prow
# entrypoint for PRs to this repo, as well as for PRs on other repos,
# mainly coreos-assembler.  It assumes that `cosa init` has been run.

REDIRECTOR_URL="https://rhcos-redirector.apps.art.xq1c.p1.openshiftapps.com/art/storage/releases/"

# record information about cosa + rpm-ostree
if test -d /cosa; then
    jq . < /cosa/coreos-assembler-git.json
fi
rpm-ostree --version

# We generate .repo files which write to the source, but
# we captured the source as part of the Docker build.
# In OpenShift default SCC we'll run as non-root, so we need
# to make a new copy of the source.  TODO fix cosa to be happy
# if src/config already exists instead of wanting to reference
# it or clone it.  Or we could write our .repo files to a separate
# place.
if test '!' -w src/config; then
    git clone --recurse src/config src/config.writable
    rm src/config -rf
    mv src/config.writable src/config
fi

# Grab the raw value of `mutate-os-release` and use sed to convert the value
# to X-Y format
ocpver=$(rpm-ostree compose tree --print-only src/config/manifest.yaml | jq -r '.["mutate-os-release"]')
ocpver_mut=$(rpm-ostree compose tree --print-only src/config/manifest.yaml | jq -r '.["mutate-os-release"]' | sed 's|\.|-|')
prev_build_url=${REDIRECTOR_URL}/rhcos-${ocpver}/
# we want to use RHEL 8.5 for testing until we can start using 8.6
# see https://github.com/openshift/release/pull/26193
curl -L http://base-"${ocpver_mut}"-rhel86.ocp.svc.cluster.local > src/config/ocp.repo
cosa buildfetch --url=${prev_build_url}
cosa fetch
cosa build
cosa buildextend-extensions
# Manually exclude Secure Boot testing for pre-release RHEL content.
# This will be removed once RHEL 8.6 is GA.
# See https://github.com/openshift/os/pull/756
# cosa kola --basic-qemu-scenarios
cosa kola run --qemu-nvme=true basic
cosa kola run --qemu-firmware=uefi basic
kola run-upgrade -b rhcos -v --find-parent-image --qemu-image-dir tmp/ --output-dir tmp/kola-upgrade
cosa kola run --parallel 2
# Build metal + installer now so we can test them
cosa buildextend-metal && cosa buildextend-metal4k && cosa buildextend-live
# compress the metal and metal4k images now so we're testing
# installs with the image format we ship
cosa compress --artifact=metal --artifact=metal4k
# Running testiso scenarios on metal artifact
# Skip the following scenarios: iso-install,iso-offline-install,iso-live-login,iso-as-disk
# See: https://github.com/openshift/os/issues/666
kola testiso -S --scenarios pxe-install,pxe-offline-install --output-dir tmp/kola-metal
# iso-install scenario to sanity-check the metal4k media
# Skip all the testiso scenarios for metal4k + UEFI
# See: https://github.com/openshift/os/issues/666
# kola testiso -S --qemu-native-4k --qemu-multipath --scenarios iso-install --output-dir tmp/kola-metal4k
# if [ $(uname -i) = x86_64 ] || [ $(uname -i) = aarch64 ]; then
#     mkdir -p tmp/kola-uefi
#     kola testiso -S --qemu-firmware uefi --scenarios iso-live-login,iso-as-disk --output-dir tmp/kola-uefi/insecure
#     if [ $(uname -i) = x86_64 ]; then
#         kola testiso -S --qemu-firmware uefi-secure --scenarios iso-live-login,iso-as-disk --output-dir tmp/kola-uefi/secure
#     fi
# fi
