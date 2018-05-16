#!/bin/bash
set -xeuo pipefail

yum -y install jq
make syntax-check
# https://github.com/openshift/os/pull/32#issuecomment-389523058
# make container
