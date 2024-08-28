#!/bin/bash

check() {
    return 0
}

depends() {
    echo ignition
}

install() {
    # Installed vendored gdisk binary in the initramfs for Ignition
    # See: https://issues.redhat.com/browse/RHEL-56080
    inst /usr/libexec/ignition-sgdisk /usr/sbin/sgdisk
}
