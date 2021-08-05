#!/bin/bash
set -xeuo pipefail
# This script is the entrypoint for PRs to this repo via OpenShift Prow.
dn=$(dirname $0)
# Prow jobs don't support adding emptydir today
export COSA_SKIP_OVERLAY=1
# Create a temporary cosa workdir
cd "$(mktemp -d)"
cosa init /src
exec ${dn}/prow-build-test-qemu.sh
