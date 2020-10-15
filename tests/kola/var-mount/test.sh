#!/bin/bash
set -xeuo pipefail
# Copied from https://github.com/coreos/fedora-coreos-config/blob/a461b20b025cb9e1cae3327ff7f17eabda2d25af/tests/kola/var-mount/test.sh

# restrict to qemu for now because the primary disk path is platform-dependent
# kola: {"platforms": "qemu"}

src=$(findmnt -nvr /var -o SOURCE)
[[ $(realpath "$src") == $(realpath /dev/disk/by-partlabel/var) ]]

fstype=$(findmnt -nvr /var -o FSTYPE)
[[ $fstype == xfs ]]
