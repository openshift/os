#!/bin/bash
set -euxo pipefail

# This script is called by the OKD installer and runs in the
# local context of the bootstrap node.
# It rebases the booted operating system (e.g. Fedora CoreOS)
# to CentOS Stream CoreOS 9

# Load common functions
. /usr/local/bin/release-image.sh

# Copy manifests
# Before rebasing the bootstrap node from FCOS to SCOS, ensure the OKD manifests are in place
if [ ! -d /opt/openshift/openshift/ ]; then
    mkdir -p /opt/openshift/openshift/
fi
cp -irvf manifests/* /opt/openshift/openshift/

# Pivot to new os content
MACHINE_OS_IMAGE=$(image_for centos-stream-coreos-9)
rpm-ostree rebase --experimental "ostree-unverified-registry:${MACHINE_OS_IMAGE}"

touch /opt/openshift/.pivot-done

systemctl reboot
