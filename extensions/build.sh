#!/bin/bash
set -xeuo pipefail

# fetch repos from in-cluster mirrors if we're running in OpenShift CI
if [ "${OPENSHIFT_CI}" != 0 ]; then
    ci/get-ocp-repo.sh ocp.repo
fi

. /etc/os-release
# XXX: we can drop the rhcos check once we've dropped the `ocp-rhel-9.6` variant
if [ $ID = rhel ] || [ $ID = rhcos ]; then
    MANIFEST="manifest-rhel-9.6.yaml"
    EXTENSIONS="extensions-ocp-rhel-9.6.yaml"
else
    MANIFEST="manifest-c9s.yaml"
    EXTENSIONS="extensions-okd-c9s.yaml"
fi

rpm-ostree compose extensions --rootfs=/ \
    --output-dir=/usr/share/rpm-ostree/extensions/ \
    "${MANIFEST}" "${EXTENSIONS}"

