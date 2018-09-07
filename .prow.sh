#!/bin/bash
set -xeuo pipefail

# This script is run by prow using the coreos-assembler container.

make syntax-check
# And disable the container again until we figure out about Prow -> internal
# make container
