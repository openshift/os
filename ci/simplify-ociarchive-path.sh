#!/bin/bash
# Give the newly-built OCI archive a predictable filename to make OCI archive
# extraction / ingestion simpler in Prow.

set -xeuo

arch="x86_64"
cosa_build_id="$(cat "${COSA_DIR}/builds/builds.json" | jq -r '.builds[0].id')"
current_build_dir="${COSA_DIR}/builds/latest/${arch}"
mv "${current_build_dir}/rhcos-${cosa_build_id}-ostree.${arch}.ociarchive" "${current_build_dir}/rhcos.${arch}.ociarchive"
