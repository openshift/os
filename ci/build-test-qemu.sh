#!/bin/bash -xe
exec gangplank pod --namespace coreos --serviceaccount coreos-builder --spec /src/ci/build-test-qemu.sh
