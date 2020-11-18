#!/bin/bash
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh

depends() {
    echo systemd
}

install() {
    inst_simple "$moddir/10-default-env-godebug.conf" \
        "/etc/systemd/system.conf.d/10-default-env-godebug.conf"
}
