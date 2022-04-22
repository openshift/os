#!/bin/bash
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh

# We want to provide Azure udev rules as part of the initrd, so that Ignition
# is able to detect disks and act on them.
#
# The WALinuxAgent-udev has been changed to install udev rules into
# the initramfs [1], but that change isn't in el8 yet. This can be
# dropped when moving to el9.
#
# [1] https://src.fedoraproject.org/rpms/WALinuxAgent/c/521b67bc8575f53a30b4b2c4e63292e67483a4e1?branch=rawhide 

install() {
    inst_multiple \
        /usr/lib/udev/rules.d/66-azure-storage.rules \
        /usr/lib/udev/rules.d/99-azure-product-uuid.rules
}
