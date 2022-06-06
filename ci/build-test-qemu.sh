#!/bin/bash
set -xeuo pipefail
# This script is the entrypoint for PRs to this repo via OpenShift Prow.
dn=$(dirname $0)
# Prow jobs don't support adding emptydir today
export COSA_SKIP_OVERLAY=1
# Create a temporary cosa workdir if COSA_DIR is not set.
export COSA_DIR="${COSA_DIR:-$(mktemp -d)}"
cd "$COSA_DIR"
exec "${dn}/prow-build-test-qemu.sh"
