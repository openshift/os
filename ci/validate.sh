#!/bin/bash
set -xeuo pipefail

# Create a temporary copy
workdir="$(mktemp -d)"
echo "Using $workdir as working directory"
cd "$workdir"
git clone /go/src/github.com/openshift/os os
cd os
# First ensure submodules are initialized
git submodule update --init --recursive
# Basic syntax check
./fedora-coreos-config/ci/validate
