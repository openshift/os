#!/bin/bash
set -xeuo pipefail
# record information about cosa + rpm-ostree
if test -d /cosa; then
    jq . < /cosa/coreos-assembler-git.json
fi
rpm-ostree --version
# Prow jobs don't support adding emptydir today
export COSA_SKIP_OVERLAY=1
# We generate .repo files which write to the source, but
# we captured the source as part of the Docker build.
# In OpenShift default SCC we'll run as non-root, so we need
# to make a new copy of the source.  TODO fix cosa to be happy
# if src/config already exists instead of wanting to reference
# it or clone it.  Or we could write our .repo files to a separate
# place.
tmpsrc=$(mktemp -d)
# Create a temporary cosa workdir
cd "$(mktemp -d)"
# This script runs on PRs to openshift/os *and* it should
# support being called externally, in which case we expect
# the git URI to be passed as an argument.
if test -n "${1:-}"; then
    git clone --depth=1 --recurse "$1" "${tmpsrc}/src"
else
    # We're being run in openshift/os as part of Prow, which
    # built a `src` container with the code under test.
    cp -a /src "${tmpsrc}"/src
fi
cosa init "${tmpsrc}"/src
# Grab the raw value of `mutate-os-release` and use sed to convert the value
# to X-Y format
ocpver=$(rpm-ostree compose tree --print-only src/config/manifest.yaml | jq -r '.["mutate-os-release"]' | sed 's|\.|-|')
curl -L http://base-"${ocpver}"-rhel8.ocp.svc.cluster.local > src/config/ocp.repo
cosa fetch
cosa build
cosa buildextend-extensions
cosa kola --basic-qemu-scenarios
cosa kola run 'ext.*'
# TODO: all tests in the future, but there are a lot
# and we want multiple tiers, and we need to split them
# into multiple pods and stuff.
