#!/bin/bash

# NVMe by-id/ symlinks changed wrt leading spaces from RHEL8 to RHEL9:
# https://issues.redhat.com/browse/OCPBUGS-11375
# https://github.com/systemd/systemd/issues/27155

# This rule adds back the previous symlinks for backwards compatibility. We want
# it in the initramfs in case there are Ignition configs which referenced the
# old symlinks.

install() {
    inst_multiple /usr/lib/udev/rules.d/61-persistent-storage-nvme-compat.rules
}
