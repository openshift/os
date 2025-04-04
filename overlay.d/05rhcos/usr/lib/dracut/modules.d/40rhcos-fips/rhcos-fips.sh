#!/bin/bash
set -euo pipefail

IGNITION_CONFIG=/run/ignition.json
# https://github.com/openshift/machine-config-operator/pull/868
MACHINE_CONFIG_ENCAPSULATED=/etc/ignition-machine-config-encapsulated.json

main() {
    mode=$1; shift
    case "$mode" in
        firstboot) firstboot;;
        finish) finish;;
        *) fatal "Invalid mode $mode";;
    esac
}

firstboot() {
    if [ "$(</proc/sys/crypto/fips_enabled)" -eq 1 ]; then
        noop "FIPS mode is enabled."
    fi

    # Make sure the Ignition messages made it to disk before querying
    # https://bugzilla.redhat.com/show_bug.cgi?id=1862957
    journalctl --sync

    # See https://github.com/coreos/fedora-coreos-config/commit/65de5e0f1676fa20537caa781937c1632eee5718
    # And see https://github.com/coreos/ignition/pull/958 for the MESSAGE_ID source.
    ign_usercfg_msg=$(journalctl -q MESSAGE_ID=57124006b5c94805b77ce473e92a8aeb IGNITION_CONFIG_TYPE=user)
    if [ -z "${ign_usercfg_msg}" ]; then
        noop "No Ignition config provided."
    fi
    if [ ! -f "${IGNITION_CONFIG}" ]; then
        fatal "Missing ${IGNITION_CONFIG}"
    fi

    local tmp=/run/rhcos-fips
    local tmpsysroot="${tmp}/sysroot"
    coreos-dummy-ignition-files-run "${tmp}" "${IGNITION_CONFIG}" "${MACHINE_CONFIG_ENCAPSULATED}"

    if [ ! -f "${tmpsysroot}/${MACHINE_CONFIG_ENCAPSULATED}" ]; then
        noop "No ${MACHINE_CONFIG_ENCAPSULATED} found in Ignition config"
    fi

    echo "Found ${MACHINE_CONFIG_ENCAPSULATED} in Ignition config"

    # don't use -e here to distinguish between false/null
    case $(jq .spec.fips "${tmpsysroot}/${MACHINE_CONFIG_ENCAPSULATED}") in
        false) noop "FIPS mode not requested";;
        true) ;;
        *)
            cat "${tmpsysroot}/${MACHINE_CONFIG_ENCAPSULATED}"
            fatal "Missing/malformed FIPS field"
            ;;
    esac

    echo "FIPS mode required; updating BLS entry"

    rdcore kargs --boot-device /dev/disk/by-label/boot \
        --append fips=1 --append boot=LABEL=boot

    echo "Scheduling reboot"
    # Write to /run/coreos-kargs-reboot to inform the reboot service so we
    # can apply both kernel arguments & FIPS without multiple reboots
    > /run/coreos-kargs-reboot
}

finish() {
    if [ "$(</proc/sys/crypto/fips_enabled)" -ne 1 ]; then
        fatal "FIPS mode is not enabled."
    fi

    # on EL10 fips-mode-setup was removed and these steps are
    # no longer needed. Please delete this function and sysroot_bwrap
    # when EL9 is no longer supported.
    if [ ! -e /sysroot/usr/bin/fips-mode-setup ]; then
        return 0
    fi

    # If we're running from a live system, then set things up so that the dracut fips
    # module will find the kernel binary.  TODO change dracut to look in /usr/lib/modules/$(uname -r)
    # directly.
    if test -f /etc/coreos-live-initramfs; then
        # See the dracut source
        rhevh_livedir=/run/initramfs/live
        mkdir -p "${rhevh_livedir}"
        # Why "vmlinuz0"?  I have no idea; it's what the dracut fips module uses.
        ln -sr /usr/lib/modules/$(uname -r)/vmlinuz ${rhevh_livedir}/vmlinuz0
    fi

    # This is analogous to Anaconda's `chroot /sysroot fips-mode-setup`. Though
    # of course, since our approach is "Ignition replaces Anaconda", we have to
    # do it on firstboot ourselves. The key part here is that we do this
    # *before* the initial switch root.
    sysroot_bwrap fips-mode-setup --enable --no-bootcfg
}

sysroot_bwrap() {
    # Need to work around the initrd `rootfs` / filesystem not being a valid
    # mount to pivot out of. See:
    # https://github.com/torvalds/linux/blob/26bc672134241a080a83b2ab9aa8abede8d30e1c/fs/namespace.c#L3605
    # See similar code in: https://gist.github.com/jlebon/fb6e7c6dcc3ce17d3e2a86f5938ec033
    mkdir -p /mnt/bwrap
    mount --bind / /mnt/bwrap
    mount --make-private /mnt/bwrap
    mount --bind /mnt/bwrap /mnt/bwrap
    for mnt in proc sys dev; do
      mount --bind /$mnt /mnt/bwrap/$mnt
    done
    touch /mnt/bwrap/run/ostree-booted
    mount --rbind /sysroot /mnt/bwrap/sysroot
    chroot /mnt/bwrap env --chdir /sysroot bwrap \
        --unshare-pid --unshare-uts --unshare-ipc --unshare-net \
        --unshare-cgroup-try --dev /dev --proc /proc --chdir / \
        --ro-bind usr /usr --bind etc /etc --dir /tmp --tmpfs /var/tmp \
        --tmpfs /run --ro-bind /run/ostree-booted /run/ostree-booted \
        --symlink usr/lib /lib \
        --symlink usr/lib64 /lib64 \
        --symlink usr/bin /bin \
        --symlink usr/sbin /sbin -- "$@"
}

noop() {
    echo "$@"
    exit 0
}

fatal() {
    echo "$@"
    exit 1
}

main "$@"
