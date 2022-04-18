#!/bin/bash
set -xeuo pipefail

# Prow jobs don't support adding emptydir today
export COSA_SKIP_OVERLAY=1
# Create a temporary cosa workdir if COSA_DIR is not set.
cosa_dir="${COSA_DIR:-$(mktemp -d)}"
echo "Using $cosa_dir for build"
cd "$cosa_dir"
cosa init /src

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

# Grab the raw value of `mutate-os-release` and use sed to convert the value
# to X-Y format
ocpver=$(rpm-ostree compose tree --print-only src/config/manifest.yaml | jq -r '.["mutate-os-release"]')
ocpver_mut=$(rpm-ostree compose tree --print-only src/config/manifest.yaml | jq -r '.["mutate-os-release"]' | sed 's|\.|-|')
prev_build_url=${REDIRECTOR_URL}/rhcos-${ocpver}/
# temporarily also fetch 8.5 repo for sssd
# https://bugzilla.redhat.com/show_bug.cgi?id=2072050
curl -L http://base-"${ocpver_mut}"-rhel86.ocp.svc.cluster.local > src/config/ocp.repo
curl -L http://base-"${ocpver_mut}"-rhel85.ocp.svc.cluster.local > src/config/ocp85.repo
sed -i -e 's,\[rhel-8-,\[rhel-85-,' src/config/ocp85.repo
cosa buildfetch --url=${prev_build_url}
cosa fetch
cosa build
cosa buildextend-extensions

# Give the newly-built OCI archive a predictable filename to make OCI archive extraction simpler
arch="x86_64"
cosa_build_id="$(cat "${COSA_DIR}/builds/builds.json" | jq -r '.builds[0].id')"
current_build_dir="${COSA_DIR}/builds/latest/${arch}"
mv "${current_build_dir}/rhcos-${cosa_build_id}-ostree.${arch}.ociarchive" "${current_build_dir}/rhcos.${arch}.ociarchive"
