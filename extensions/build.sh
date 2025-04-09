#!/bin/bash
set -xeuo pipefail

# fetch repos from in-cluster mirrors if we're running in OpenShift CI
if [ "${OPENSHIFT_CI}" != 0 ]; then
    ci/get-ocp-repo.sh ocp.repo
fi

. /etc/os-release
# XXX: we can drop the rhcos check once we've dropped the `ocp-rhel-9.6` variant
if [ $ID = rhel ] || [ $ID = rhcos ]; then
    # For now, while we are still building the `4.19-9.6` stream the
    # $VERSION_ID for those will be the openshift version while
    # $RHEL_VERSION will be the RHEL version. Let's detect that situation
    # here and use RHEL_VERSION if it exists. We should be able to drop
    # this soon.
    manifest_version="${RHEL_VERSION:-$VERSION_ID}"
    MANIFEST="manifest-rhel-${manifest_version}.yaml"
    EXTENSIONS="extensions-ocp-rhel-${manifest_version}.yaml"
else
    MANIFEST="manifest-c${VERSION_ID}s.yaml"
    EXTENSIONS="extensions-okd-c${VERSION_ID}s.yaml"
fi

rpm-ostree compose extensions --rootfs=/ \
    --output-dir=/usr/share/rpm-ostree/extensions/ \
    "${MANIFEST}" "${EXTENSIONS}"

