#!/bin/bash
# -*- mode: shell-script; indent-tabs-mode: nil; sh-basic-offset: 4; -*-
# ex: ts=8 sw=4 sts=4 et filetype=sh

# These udev rules support certain VM types that present managed disks as
# NVMe devices instead of traditional SCSI devices (e.g. Standard_M16bds_v3,
# Standard_M16bs_v3, Standard_L8s_v4). The rules allow the Azure Disk CSI
# driver to perform LUN-based disk detection when mounting these NVMe disks.
# The azure-vm-utils package provides these udev rules[1], but it wont be added
# until EL10 [2]. This can be dropped when moving to EL10, provided the
# package is included at that time.
#
# [1] https://github.com/Azure/azure-vm-utils/blob/9c596916b6774f24420dac0ee7a72a6c9ddb5060/udev/80-azure-disk.rules
# [2] https://issues.redhat.com/browse/RHEL-73904

install() {
    inst_rules /usr/lib/udev/rules.d/80-azure-disk.rules
}
