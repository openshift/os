#!/bin/bash
set -xeuo pipefail

dn="$(dirname "$0")"

# Create a temporary cosa workdir if COSA_DIR is not set.
export COSA_DIR="${COSA_DIR:-$(mktemp -d)}"

"$dn/prow-build.sh"
cosa kola --basic-qemu-scenarios
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
