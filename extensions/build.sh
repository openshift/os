#!/bin/bash
set -xeuo pipefail

# fetch repos from in-cluster mirrors if we're running in OpenShift CI
if [ "${OPENSHIFT_CI}" != 0 ]; then
    ci/get-ocp-repo.sh ocp.repo
fi

. /etc/os-release
extensions_yaml="extensions/${ID}-${VERSION_ID}.yaml"
# Replace the __OCP_VERSION__ placeholder with the actual OpenShift version.
# This allows the same YAML file to be used across different OCP versions
# (e.g. 4.23 and 5.0) without duplication.
sed -i "s/__OCP_VERSION__/${OPENSHIFT_VERSION}/g" "$extensions_yaml"

# Detect if this is an ART build by checking for:
# 1. The mounted secret.repo file (has content)
# 2. OR the .oit directory (indicates ART rebase was done)
# ART builds inject repos via secret.repo at rebase time OR via .oit/art-unsigned.repo
# in the source directory, so we can use the dnf-based approach which ignores
# the repos: section in the YAML.
# Local/Prow builds don't have these indicators, so they need the rpm-ostree approach
# which uses the repos: section from the YAML.
if [ -s /os/secret.repo ] || [ -d .oit ]; then
    echo "Detected ART build, using dnf-based approach"
    # For ART builds, repos are already in /etc/yum.repos.d/ via secret.repo mount
    # or via the rebase modifications to the Dockerfile
    # Build extensions using dnf to download packages.
    # This uses repos from /etc/yum.repos.d/ and ignores repos: sections in the YAML.
    mkdir -p /usr/share/rpm-ostree/extensions/
    python3 extensions/build_extensions.py "$extensions_yaml"
else
    echo "Detected local/Prow build (no ART indicators), using rpm-ostree approach"
    # just to parse the treefile, rpm-ostree still wants to read referenced "externals" (e.g. passwd, group)
    # hack around this for now by deleting the problematic bits; we should tweak rpm-ostree instead
    jq 'del(.["check-passwd","check-groups"])' /usr/share/rpm-ostree/treefile.json > filtered.json

    # Build extensions using rpm-ostree which respects repos: sections in the YAML
    rpm-ostree compose extensions filtered.json "$extensions_yaml" \
        --rootfs=/ --output-dir=/usr/share/rpm-ostree/extensions/
fi
