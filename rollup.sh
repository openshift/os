#!/usr/bin/bash
# This script aggregates content
set -xeuo pipefail
mkdir -p /srv/tree
cd /srv/tree
ostree --repo=repo init --mode=archive
ostree --repo=repo remote add remote --set=gpg-verify=false ${OSTREE_REPO_URL:-}
ostree --repo=repo pull --mirror --depth=3 remote
