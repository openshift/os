#!/bin/bash
set -xeuo pipefail

# fetch repos from in-cluster mirrors if we're running in OpenShift CI
if [ "${OPENSHIFT_CI}" != 0 ]; then
    ci/get-ocp-repo.sh ocp.repo
fi

# just to parse the treefile, rpm-ostree still wants to read referenced "externals" (e.g. passwd, group)
# hack around this for now by deleting the problematic bits; we should tweak rpm-ostree instead
jq 'del(.["check-passwd","check-groups"])' /usr/share/rpm-ostree/treefile.json > filtered.json

# The base image treefile references rhel-9.8-* repo names, but we use rhel-9-*
# repos in CI for pre-release content (see ci/get-ocp-repo.sh). Rewrite the repo
# names to match. rhel-9.8-early-kernel is excluded because it exists under the
# same name in both repo sets.
jq '.repos |= map(if startswith("rhel-9.8-") and . != "rhel-9.8-early-kernel"
                  then "rhel-9-" + ltrimstr("rhel-9.8-")
                  else . end)' \
    filtered.json > filtered.json.tmp && mv filtered.json{.tmp,}

. /etc/os-release
rpm-ostree compose extensions filtered.json "extensions/${ID}-${VERSION_ID}.yaml" \
    --rootfs=/ --output-dir=/usr/share/rpm-ostree/extensions/
