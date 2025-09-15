#!/bin/bash
set -euo pipefail

# This script is used when running within the OpenShift CI clusters to fetch
# the RHEL and OCP yum repo files from an in-cluster service that mirrors the
# content.

urls=(
    # theoretically that's the only one we need
    "http://base-4-21-rhel96.ocp.svc.cluster.local"
)

dest=$1; shift

rm -f "$dest"
for url in "${urls[@]}"; do
    curl --fail -L "$url" >> "$dest"
done
