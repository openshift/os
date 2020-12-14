#!/bin/bash
# The latest Dracut release that landed in RHEL 8.3 stopped creating
# `$systemdsystemunitdir/initrd.target.wants` dir, causing
# `kdump-capture.service` to not be installed correctly and thus making
# kdump unable to capture the vmcore during a kernel panic.
# There is a patch in kexec-tools to address this issue
# https://bugzilla.redhat.com/show_bug.cgi?id=1907253.
# For now, we will create this directory ourselves, but we should drop
# this once the proper kexec-tools patches land.

check() {
    return 0
}

depends() {
    return 0
}

install() {
    mkdir -p "$initdir/$systemdsystemunitdir/initrd.target.wants"
}
