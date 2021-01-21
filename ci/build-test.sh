#!/bin/bash
set -xeuo pipefail
# First ensure submodules are initialized
git submodule update --init --recursive
# Basic syntax check
./fedora-coreos-config/ci/validate
# Prow jobs don't support adding emptydir today
export COSA_SKIP_OVERLAY=1
gitdir=$(pwd)
cd $(mktemp -d)
cosa init ${gitdir}
# TODO query the 4-7 bits from manifest.yaml or so
curl -L http://base-4-7-rhel8.ocp.svc.cluster.local > src/config/ocp.repo
cosa fetch
cosa build
cosa kola --basic-qemu-scenarios
cosa kola run 'ext.*'
# TODO: all tests in the future, but there are a lot
# and we want multiple tiers, and we need to split them
# into multiple pods and stuff.
