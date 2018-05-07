#!/bin/bash
set -xeuo pipefail

yum -y install jq
for jsonfile in *.json; do
    echo "Checking JSON syntax for $jsonfile"
    jq < $jsonfile . >/dev/null
done

imagebuild -privileged .
