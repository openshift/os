#!/bin/bash
set -xeuo
/src/ci/set-openshift-user.sh
/src/ci/prow-build.sh
cosa kola run --parallel 2

