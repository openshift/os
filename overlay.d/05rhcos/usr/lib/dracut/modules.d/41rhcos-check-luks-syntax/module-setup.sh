#!/bin/bash

install_unit() {
    local unit="$1"; shift
    local target="${1:-ignition-complete.target}"; shift
    local instantiated="${1:-$unit}"; shift
    inst_simple "$moddir/$unit" "$systemdsystemunitdir/$unit"
    systemctl -q --root="$initdir" add-requires "$target" "$instantiated"
}

install() {
    inst_script "$moddir/rhcos-fail-boot-for-legacy-luks-config" \
        "/usr/libexec/rhcos-fail-boot-for-legacy-luks-config"
    
    install_unit rhcos-fail-boot-for-legacy-luks-config.service
}
