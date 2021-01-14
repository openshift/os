#!/bin/bash
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh

install() {
    # mke2fs in RHEL fails without /etc/mke2fs.conf
    # https://bugzilla.redhat.com/show_bug.cgi?id=1889464
    # https://bugzilla.redhat.com/show_bug.cgi?id=1916382
    inst /etc/mke2fs.conf
}
