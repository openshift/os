#!/bin/bash
set -xeuo
/src/ci/set-openshift-user.sh
/src/ci/prow-build.sh
kola run-upgrade -b rhcos -v --find-parent-image --qemu-image-dir tmp/ --output-dir tmp/kola-upgrade

