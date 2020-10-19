#!/bin/bash
set -xeuo pipefail
# First ensure submodules are initialized
git submodule update --init --recursive
# Basic syntax check
./fedora-coreos-config/ci/validate
# To be expanded with a cosa build
