#!/bin/bash -xe
# Use Gangplank in dumb mode for now.
gangplank podless --srvDir /tmp --spec /src/ci/build-test-qemu.yaml
