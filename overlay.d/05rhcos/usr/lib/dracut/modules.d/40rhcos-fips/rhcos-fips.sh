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
        exit 0
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

    echo "FIPS mode required; updating BLS entries"

    mkdir -p "${tmpsysroot}/boot"
    mount /dev/disk/by-label/boot "${tmpsysroot}/boot"

    for f in "${tmpsysroot}"/boot/loader/entries/*.conf; do
        echo "Appending 'fips=1 boot=LABEL=boot' to ${f}"
        sed -e "/^options / s/$/ fips=1 boot=LABEL=boot/" -i "$f"
    done
    sync -f "${tmpsysroot}/boot"

    if [[ $(uname -m) = s390x ]]; then
      # Similar to https://github.com/coreos/coreos-assembler/commit/100c2e512ecb89786a53bfb1c81abc003776090d in the coreos-assembler
      # We need to call zipl with the kernel image and ramdisk as running it without these options would require a zipl.conf and chroot
      # into rootfs
      tmpfile=$(mktemp)
      optfile=$(mktemp)
      for f in "${tmpsysroot}"/boot/loader/entries/*.conf; do
          for line in title version linux initrd options; do
              echo $(grep $line $f) >> $tmpfile
          done
      done
      echo "Appending 'ignition.firstboot' to ${optfile}"
      options="$(grep options $tmpfile | cut -d ' ' -f2-) ignition.firstboot"
      echo $options > "$optfile"
      zipl --verbose \
           --target "${tmpsysroot}/boot" \
           --image $tmpsysroot/boot/"$(grep linux $tmpfile | cut -d' ' -f2)" \
           --ramdisk $tmpsysroot/boot/"$(grep initrd $tmpfile | cut -d' ' -f2)" \
           --parmfile $optfile
    fi

    # Write to /run/fips-modified to inform the reboot service so we can apply both kernel arguments & FIPS
    # without multiple reboots
    echo "modified" > /run/fips-modified
}

finish() {
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
    mount --bind /sysroot /mnt/bwrap/sysroot
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
