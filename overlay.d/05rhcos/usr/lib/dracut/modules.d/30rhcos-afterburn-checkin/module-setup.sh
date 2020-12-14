# RHCOS specific initramfs checkin for Azure. Linked to
# initrd.target much like what we do for ignition
#
# Context: this is for installer UX considerations. The provision
# success check masks issues with Ignition configs because it runs
# after Ignition (which may never conclude). Terraform will also
# report that nothing is progressing (as it is waiting for the checkin
# even though things are. Kube will do the actual health handling
# for the machine.

depends() {
    echo network systemd
}

check() {
    return 0
}

install() {
    local unit=rhcos-afterburn-checkin.service
    inst_simple "$moddir/$unit" "$systemdsystemunitdir/$unit"
    systemctl -q --root="$initdir" add-requires ignition-files.service "$unit"
}
