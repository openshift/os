#!/bin/bash

# This script performs the following tasks:
#
# 1. Logs into the rhcos-devel service account to get the image push credential
# so we can push to the registry.ci.openshift.org/rhcos-devel namespace.
#
# 2. Kicks off the build-test-qemu.sh script to build and test an RHCOS image
# with Kola tests.
#
# 3. Pushes the resulting image to the image registry using the Prow build ID
# as the tag since we need to have the image in this registry so our derived
# image build test can use it.
#
# 3. Kicks off the derived OS image testing binary which pulls the newly built
# image, builds a derived image from it, applies it to an underlying OpenShift
# cluster node, verifies that it was successfully applied, then rolls the node
# back.

set -euo pipefail

# Notes:
# - The oc binary will be injected by the Prow CI process. It is not present in
# ci/Dockerfile.
# - When we log into the main CI cluster to get the registry creds, oc mutates
# the kubeconfig for the ephemeral cluster we run our derived image tests
# against. We temporarily set $KUBECONFIG to an empty file so that file gets
# mutated during the login phase.
tmp_kubeconfig="$(mktemp)"
KUBECONFIG="$tmp_kubeconfig" oc login https://api.ci.l2s4.p1.openshiftapps.com:6443 --token="$(cat /service-account-token/image-pusher-service-account-token)"
KUBECONFIG="$tmp_kubeconfig" oc registry login --registry=registry.ci.openshift.org --to="$SHARED_DIR/dockercfg.json";

export COSA_DIR="/tmp/cosa"
mkdir -p "$COSA_DIR"

# Run the cosa build / test
/src/ci/build-test-qemu.sh

export REGISTRY_AUTH_FILE="$SHARED_DIR/dockercfg.json"

# Ensure we're in the designated cosa directory so the push-container commands work
cd "$COSA_DIR"

# Tags with the cosa build ID / arch - unique to this specific build
cosa push-container registry.ci.openshift.org/rhcos-devel/rhel-coreos

# Tag with the Prow Build ID because we don't want to overwrite our well-known
# tags yet, but our test cluster needs the image to be pushed someplace so we
# can ingest it. We use the BUILD_ID value because its unique to each job so
# they won't stomp on each other if running concurrently.
#
# TODO: Aim to push this to the ephemeral CI namespace registry before making
# the final push at the end.
export BASE_IMAGE_PULLSPEC="registry.ci.openshift.org/rhcos-devel/rhel-coreos:$BUILD_ID"
cosa push-container "$BASE_IMAGE_PULLSPEC"

# Perform the derived OS image build tests
/usr/local/bin/layering_test -test.v -test.failfast -test.timeout 35m -build-log="$ARTIFACT_DIR/derived-image-build.log"
