#!/bin/bash
# Temporarily keep this script to let us merge over green CI.
# Can be removed once we've merged the openshift/release changes.
set -xeuo pipefail
dn="$(dirname $0)"
# Prow jobs don't support adding emptydir today
export COSA_SKIP_OVERLAY=1
exec "${dn}/prow-entrypoint.sh" "rhcos-86-build-test-qemu"
