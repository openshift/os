#!/bin/bash
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh

depends() {
    echo ignition
}

# FCOS carries the `base.ign` file in
# https://github.com/coreos/fedora-coreos-config/blob/testing-devel/overlay.d/05core/usr/lib/dracut/modules.d/40ignition-conf/base.ign
# RHCOS doesn't need `afterburn-sshkeys@core.service`. Therefore, RHCOS
# maintains its own copy of `base.ign`, and changes to one copy need to
# be synced to the other copy.
# See https://github.com/coreos/fedora-coreos-config/pull/626
install() {
    test -f $initdir/usr/lib/ignition/base.ign
    inst "$moddir/base.ign" \
        "/usr/lib/ignition/base.ign"
}
