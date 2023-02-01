#!/bin/bash
# TODO: share this with ci/prow-entrypoint.sh
set -euo pipefail
ocpver=$(rpm-ostree compose tree --print-only manifest.yaml | jq -r '.["mutate-os-release"]')
ocpver_mut=$(rpm-ostree compose tree --print-only manifest.yaml | jq -r '.["mutate-os-release"]' | sed 's|\.|-|')
rhelver=$(rpm-ostree compose tree --print-only manifest.yaml | jq -r '.["automatic-version-prefix"]' | cut -f2 -d.)

set -x
curl --fail -L "http://base-${ocpver_mut}-rhel${rhelver}.ocp.svc.cluster.local" -o "ocp.repo"
cat ocp.repo
