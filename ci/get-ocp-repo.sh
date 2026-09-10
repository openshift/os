#!/bin/bash
set -euo pipefail

# This script is used when running within the OpenShift CI clusters to fetch
# the RHEL and OCP yum repo files from an in-cluster service that mirrors the
# content.

required_urls=(
    "http://base-5-0-rhel98.ocp.svc.cluster.local"
    "http://base-5-0-rhel102.ocp.svc.cluster.local"
)

# 5.1 mirrors are needed when CI tests the master variant (which now
# tracks OCP 5.1) against this release-5.0 branch.
optional_urls=(
    "http://base-5-1-rhel98.ocp.svc.cluster.local"
    "http://base-5-1-rhel102.ocp.svc.cluster.local"
)

dest=$1; shift

rm -f "$dest"
for url in "${required_urls[@]}"; do
    curl --fail -L "$url" >> "$dest"
done
for url in "${optional_urls[@]}"; do
    curl --fail -L "$url" >> "$dest" || true
done
