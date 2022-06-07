#!/bin/bash
set -xeuo pipefail

# Prow jobs don't support adding emptydir today
export COSA_SKIP_OVERLAY=1
# Create a temporary cosa workdir if COSA_DIR is not set.
cosa_dir="${COSA_DIR:-$(mktemp -d)}"
echo "Using $cosa_dir for build"
cd "$cosa_dir"
cosa init --transient /src

# This script is called via build.sh which is the main Prow
# entrypoint for PRs to this repo, as well as for PRs on other repos,
# mainly coreos-assembler.  It assumes that `cosa init` has been run.

REDIRECTOR_URL="https://rhcos-redirector.apps.art.xq1c.p1.openshiftapps.com/art/storage/releases/"

# record information about cosa + rpm-ostree
if test -d /cosa; then
    jq . < /cosa/coreos-assembler-git.json
fi
rpm-ostree --version

# We generate .repo files which write to the source, but
# we captured the source as part of the Docker build.
# In OpenShift default SCC we'll run as non-root, so we need
# to make a new copy of the source.  TODO fix cosa to be happy
# if src/config already exists instead of wanting to reference
# it or clone it.  Or we could write our .repo files to a separate
# place.
if test '!' -w src/config; then
    git clone --recurse src/config src/config.writable
    rm src/config -rf
    mv src/config.writable src/config
fi

#
# NOTE: If you are adjusting how the repos are fetched in this script, you
#        must also make the same change in the `prow-build-test-qemu.sh` script
#
# Grab the raw value of `mutate-os-release` and use sed to convert the value
# to X-Y format
ocpver=$(rpm-ostree compose tree --print-only src/config/manifest.yaml | jq -r '.["mutate-os-release"]')
ocpver_mut=$(rpm-ostree compose tree --print-only src/config/manifest.yaml | jq -r '.["mutate-os-release"]' | sed 's|\.|-|')
prev_build_url=${REDIRECTOR_URL}/rhcos-${ocpver}/
# we want to use RHEL 8.5 for testing until we can start using 8.6
# see https://github.com/openshift/release/pull/26193
curl -L http://base-"${ocpver_mut}"-rhel85.ocp.svc.cluster.local > src/config/ocp.repo
# fetch the 8.6 appstream repo to enable building of extensions
# see: https://github.com/openshift/os/issues/795
curl -Ls http://base-"${ocpver_mut}"-rhel86.ocp.svc.cluster.local | grep -A 3 rhel-8-appstream | sed '1,3 s/rhel-8-appstream/rhel-86-appstream/g' >> src/config/ocp.repo
cosa buildfetch --url=${prev_build_url}
cosa fetch
cosa build
cosa buildextend-extensions
