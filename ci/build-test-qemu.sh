#!/bin/bash
set -xeuo pipefail
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
cp -a /src "${tmpsrc}"/src
# Create a temporary cosa workdir
cd "$(mktemp -d)"
cosa init "${tmpsrc}"/src
# Grab the raw value of `mutate-os-release` and use sed to convert the value
# to X-Y format
ocpver=$(rpm-ostree compose tree --print-only src/config/manifest.yaml | jq -r '.["mutate-os-release"]' | sed 's|\.|-|')
curl -L http://base-"${ocpver}"-rhel84.ocp.svc.cluster.local > src/config/ocp.repo
cosa fetch
cosa build
cosa buildextend-extensions
# Manually exclude Secure Boot testing for pre-release RHEL content.
# This will be removed once RHEL 8.4 is GA.
# See https://github.com/openshift/os/pull/527
# cosa kola --basic-qemu-scenarios
cosa kola run --qemu-nvme=true basic
cosa kola run --qemu-firmware=uefi basic
cosa kola run 'ext.*'
# TODO: all tests in the future, but there are a lot
# and we want multiple tiers, and we need to split them
# into multiple pods and stuff.
