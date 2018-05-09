#!/bin/bash
set -xeuo pipefail

yum -y install jq
make syntax-check
make container
