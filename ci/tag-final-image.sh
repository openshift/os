#!/bin/bash

# This script performs the following tasks:
#
# 1. Reads the jobspec to get the active branch so we know what tag
# to use.
#
# 2. Tags the image tagged with the Prow build ID to one of our
# well-known tags (e.g., master, 4.11, latest, etc.)

set -euo pipefail

# We can't use PULL_BASE_REF or OPENSHIFT_BUILD_REFERENCE to get the
# branch since this is a periodic job which originates from
# openshift/release, not the openshift/os repository. We then strip
# release- from the branch name so we're left with the number (e.g.,
# release-4.11 -> 4.11).
BRANCH="$(echo "$JOB_SPEC" | jq -r '.extra_refs[0].base_ref | sub("release-"; "")')"
export REGISTRY_AUTH_FILE="$SHARED_DIR/dockercfg.json"

skopeo copy "docker://registry.ci.openshift.org/rhcos-devel/rhel-coreos:$BUILD_ID" "docker://registry.ci.openshift.org/rhcos-devel/rhel-coreos:$BRANCH"

# Only push latest tag on master branch
if [[ "$BRANCH" == "master"  ]]; then
    skopeo copy "docker://registry.ci.openshift.org/rhcos-devel/rhel-coreos:$BUILD_ID" "docker://registry.ci.openshift.org/rhcos-devel/rhel-coreos:latest"
fi
