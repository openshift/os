#!/bin/bash
# Currently the RHT-internal `redhat-coreos` git repository
# contains both the equivalent of:
#  - fedora-coreos-config
#  - fedora-coreos-pipeline
# This script extracts just the first part, since the second
# part has way more internal stuff.
set -euo pipefail

dn=$(cd $(dirname $0) && pwd)

src=$1
shift
files=(manifest.yaml rhcos-packages.yaml image.yaml passwd group overlay.d live scripts
       kola-denylist.yaml tests)

for f in ${files[@]}; do
    rsync -rlv --delete "${src}/${f}" ${dn}
done

fcos_rev=$(cd ${src}/fedora-coreos-config && git rev-parse HEAD)
cd ${dn}/fedora-coreos-config
git fetch origin
git reset --hard "${fcos_rev}"
cd -

