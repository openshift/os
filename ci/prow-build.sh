#!/bin/bash
set -xeuo pipefail

dn="$(dirname "$0")"

# Create a temporary cosa workdir if COSA_DIR is not set.
export COSA_DIR="${COSA_DIR:-$(mktemp -d)}"
echo "Using $COSA_DIR for build"
cd "$COSA_DIR"

"$dn/prow-prepare.sh"
"$dn/cosa-build.sh"
