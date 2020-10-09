#!/bin/bash
# kola: {"platforms": "qemu", "additionalDisks": ["5G"]}
set -xeuo pipefail

srcdev=$(findmnt -nvr /var/lib/data -o SOURCE)
[[ ${srcdev} == /dev/mapper/DATA ]]

blktype=$(lsblk -o TYPE "${srcdev}" --noheadings)
[[ ${blktype} == crypt ]]

fstype=$(findmnt -nvr /var/lib/data -o FSTYPE)
[[ ${fstype} == xfs ]]
