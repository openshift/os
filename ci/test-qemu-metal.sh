#!/bin/bash
set -xeuo
/src/ci/set-openshift-user.sh
/src/ci/prow-build.sh
cosa buildextend-metal && cosa buildextend-metal4k && cosa buildextend-live
cosa compress --artifact=metal --artifact=metal4k
kola testiso -S --scenarios pxe-install,pxe-offline-install --output-dir tmp/kola-metal

