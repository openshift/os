#!/bin/bash

check() {
    return 0
}

install_unit() {
    local unit=$1; shift
    local target=${1:-ignition-complete.target}
    inst_simple "$moddir/$unit" "$systemdsystemunitdir/$unit"
    # note we `|| exit 1` here so we error out if e.g. the units are missing
    # see https://github.com/coreos/fedora-coreos-config/issues/799
    systemctl -q --root="$initdir" add-requires "$target" "$unit" || exit 1
}

depends() {
    echo bash crypt clevis fips systemd network
}

installkernel() {
    [[ $arch == x86_64 ]] && arch=x86
    [[ $arch == s390x ]] && arch=s390

    # Force installation of the required modules.
    hostonly='' instmods dm_crypt =crypto =drivers/crypto =arch/$arch/crypto =drivers/char/tpm sg
}

install() {
    # clevis should be provided by clevis, but put here explicitly
    bins=(
        blockdev
        base64
        chmod
        clevis
        clevis-decrypt
        clevis-decrypt-sss
        clevis-decrypt-tpm2
        clevis-encrypt-sss
        clevis-encrypt-tang
        clevis-encrypt-tpm2
        clevis-luks-bind
        clevis-luks-common-functions
        clevis-luks-unbind
        clevis-luks-unlock
        cryptsetup
        curl
        cut
        dd
        dirname
        growpart
        head
        jose
        jq
        luksmeta
        mktemp
        nc
        pwmake
        sfdisk
        sync
        systemd-detect-virt
        touch
        tpm2_create
        tpm2_createpolicy
        tpm2_createprimary
        tpm2_load
        tpm2_pcrread
        tpm2_unseal
        tr
        umount
    )
    inst_multiple "${bins[@]}"

    # Needed for clevis binding
    inst_dir /usr/share/cracklib
    for x in /usr/share/cracklib/*; do
        inst "${x}"
    done

    # Needed for TPM2 devices
    inst_libdir_file "libtss2-tcti-device.so*"

    inst_script /usr/libexec/coreos-cryptfs
    inst_script /usr/libexec/coreos-cryptlib

    # Service for first-boot encryption.
    inst_simple "$moddir/coreos-luks-open.service" "$systemdsystemunitdir/coreos-luks-open.service"
    # The generator enables the opening service.
    inst_simple "$moddir/coreos-luks-generator" \
        "$systemdutildir/system-generators/coreos-luks-generator"
}
