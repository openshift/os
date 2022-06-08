FROM registry.ci.openshift.org/ocp/builder:rhel-8-golang-1.17-openshift-4.10 AS builder
WORKDIR /go/src/github.com/openshift/os
COPY . .
# Prevent go mod from requiring a vendor directory.
ENV GOFLAGS=-mod=mod
# Compile our layering test binary for future use.
RUN go test -v -c -o layering_test ./tests/layering

FROM registry.svc.ci.openshift.org/coreos/coreos-assembler:latest
WORKDIR /src
ENV COSA_DIR=/tmp/cosa
# Prow doesn't support emptydir for jobs today
ENV COSA_SKIP_OVERLAY=1
COPY --from=builder /go/src/github.com/openshift/os/layering_test /usr/local/bin/layering_test
COPY . .
RUN mkdir -p "${COSA_DIR}"
# We need to make sure that root can read / write to the COSA_DIR so that
# when this container is actually run, we have permissions to read and
# write to the COSA_DIR to allow the Kola tests to run.
USER root
RUN chgrp -Rf root "${COSA_DIR}" && \
  chmod -Rf g+w "${COSA_DIR}"
USER builder
WORKDIR /tmp/cosa
