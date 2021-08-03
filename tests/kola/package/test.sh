#!/bin/bash
set -xeuo pipefail

# kola: { "architectures": "!s390x ppc64le", "minMemory": 2048,  "tags": "needs-internet" }

ok() {
    echo "ok" "$@"
    exit 0
}

fatal() {
  echo "$@"
  exit 1
}

# Verify all rhaos packages contain the same OpenShift version
test_package_versions() {
  if [[ $(rpm -qa | grep rhaos | grep -v $OPENSHIFT_VERSION) ]]; then
    fatal "Error: rhaos packages do not match OpenShift version"
  fi
}

# Verify there are no downgraded packages
test_downgraded_packages() {
  RELEASE=$OPENSHIFT_VERSION
  STREAM=fast-$RELEASE
  GRAPH=$(curl -sfH "Accept:application/json" "https://api.openshift.com/api/upgrades_info/v1/graph?channel=$STREAM")
  if [[ $? -ne 0 ]]; then
    fatal "Unable to get graph"
  fi

  # There are no released builds on master so no need to check downgraded packages
  if [[ $(echo $GRAPH | jq 'has("nodes") and has("edges") and (.nodes | length == 0)') =~ "true" ]]; then
    ok "No released stream"
  fi

  # The cincinatti graph defines nodes as a list of objects and edges as a list
  # of list of two integers. Nodes are releases, and edges are updates.
  # [x, y] is [from release index, to release index]. The release index can
  # change every request for the cincinatti graph!
  #
  # Use jq to find the node that contains no "from release index" edge.
  #   1. Find all the unique "from release indexes"
  #   2. Find all the release indexes
  #   3. Get the difference between all the releases and the "from release
  #      indexes".  This is the latest because there is no update from this
  #      release.
  PAYLOAD=$(echo $GRAPH | jq -r '. as $graph | [$graph.edges[][0]] | unique as $from | $graph.nodes | to_entries as $indexed | [$indexed[].key] | unique as $nodes | ($nodes - $from)[] as $latest | $indexed[] | select(.key == $latest) | .value.payload')
  VERSION=$(oc adm release info $PAYLOAD -o json | jq -r '.displayVersions."machine-os".Version')
  OCP_COMMIT=$(curl -sSL https://art-rhcos-ci.s3.amazonaws.com/releases/rhcos-$RELEASE/$VERSION/x86_64/meta.json | jq -r '."ostree-commit"')

  curl -SL https://art-rhcos-ci.s3.amazonaws.com/releases/rhcos-$RELEASE/$VERSION/x86_64/rhcos-$VERSION-ostree.x86_64.tar -o $STREAM.tar

  mkdir -p repo && tar xvf $STREAM.tar -C $_ && rm -rf $STREAM.tar

  ostree pull-local repo

  RHCOS_COMMIT=$(rpm-ostree status --json | jq -r .deployments[0].checksum)

  if [[ $(rpm-ostree db diff $OCP_COMMIT $RHCOS_COMMIT | grep -A1000 Downgraded) ]]; then
    fatal "Error: downgraded packages were found."
  fi
}


main() {
  cd $(mktemp -d)
  source /etc/os-release
  test_package_versions
  test_downgraded_packages
}

main

