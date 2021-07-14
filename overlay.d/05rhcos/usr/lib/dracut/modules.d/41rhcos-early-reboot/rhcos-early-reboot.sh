#!/bin/bash

set -euxo pipefail

if [ -f "/run/ignition-modified-kargs" ] || [ -f "/run/fips-modified" ]; then
    echo "Rebooting"
    systemctl --force reboot
fi
