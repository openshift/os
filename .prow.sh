#!/bin/bash
set -xeuo pipefail

yum -y install jq PyYAML
make syntax-check
# And disable the container again until we figure out about Prow -> internal
# make container
