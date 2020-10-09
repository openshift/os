#!/bin/bash
PREFIX="${1:?first argument must be the prefix}"
DISTRO="${2:?second argument must be the distro}"

out=$(oc get bc ${PREFIX}-${DISTRO} -o json 2> /dev/null \
    | jq -rM '.spec.strategy.jenkinsPipelineStrategy.env[] | select(.name== "PRODUCTION").value' 2> /dev/null)
echo ${out:-none}
