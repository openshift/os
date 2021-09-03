#!/bin/bash

check() {
    return 0
}

depends() {
    echo fips ignition
}

install() {
    inst_multiple \
        jq \
        tee \
        chroot \
        sync \
        bwrap \
        env

    inst_script "$moddir/rhcos-fips.sh" \
        "/usr/sbin/rhcos-fips"
    inst_script "$moddir/coreos-dummy-ignition-files-run.sh" \
        "/usr/sbin/coreos-dummy-ignition-files-run"
    inst_simple "$moddir/rhcos-fips.service" \
        "$systemdsystemunitdir/rhcos-fips.service"
    inst_simple "$moddir/rhcos-fips-finish.service" \
        "$systemdsystemunitdir/rhcos-fips-finish.service"

    # Unconditionally include /etc/system-fips in the initrd. This has no
    # practical effect if fips=1 isn't also enabled. OTOH, it is a *requirement*
    # for a true FIPS boot: https://bugzilla.redhat.com/show_bug.cgi?id=1778940
    echo "# RHCOS FIPS mode installation complete" > "$initdir/etc/system-fips"

    # We don't support FIPS in diskless cases currently
    target=ignition-diskful.target
    # note we `|| exit 1` here so we error out if e.g. the units are missing
    # see https://github.com/coreos/fedora-coreos-config/issues/799
    systemctl -q --root="$initdir" add-requires "$target" rhcos-fips.service || exit 1
    systemctl -q --root="$initdir" add-requires "$target" rhcos-fips-finish.service || exit 1
}
