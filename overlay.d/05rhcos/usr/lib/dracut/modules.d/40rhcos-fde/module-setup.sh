#!/bin/bash

check() {
    return 0
}

install_unit() {
    local unit=$1; shift
    local target=${1:-ignition-complete.target}
    inst_simple "$moddir/$unit" "$systemdsystemunitdir/$unit"
    local targetpath="$systemdsystemunitdir/${target}.requires/"
    mkdir -p "${initdir}/${targetpath}"
    ln_r "../$unit" "${targetpath}/${unit}"
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
        cryptsetup-reencrypt
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
        tpm2_pcrlist
        tpm2_unseal
        tr
        umount
    )
    inst_multiple ${bins[@]}

    # Needed for clevis binding
    inst_dir /usr/share/cracklib
    for x in /usr/share/cracklib/*; do
        inst $x
    done

    # Needed for TPM2 devices
    inst_libdir_file "libtss2-tcti-device.so*"

    inst_script /usr/libexec/coreos-cryptfs
    inst_script /usr/libexec/coreos-growpart
    inst_script /usr/libexec/coreos-cryptlib

    # Service for first-boot encryption.
    install_unit "coreos-fde-check-needsnet.service" "ignition-diskful.target"
    install_unit "coreos-encrypt.service" "ignition-diskful.target"
    inst_simple "$moddir/coreos-luks-open.service" "$systemdsystemunitdir/coreos-luks-open.service"
    # The generator enables the opening service.
    inst_simple "$moddir/coreos-luks-generator" \
        "$systemdutildir/system-generators/coreos-luks-generator"

    # Gate all the rootfs replacement stuff for now behind a development flag
    # since it conflicts with this module. Soon, we'll nuke this module entirely
    # anyway in its place.
    for x in ignition-ostree-rootfs-{detect,save,restore} coreos-inject-rootmap; do
        mkdir -p $initdir/$systemdsystemunitdir/${x}.service.d/
        cat > $initdir/$systemdsystemunitdir/${x}.service.d/neuter.conf <<EOF
[Unit]
ConditionKernelCommandLine=coreos.rootfs-replace.exp
EOF
    done
}
