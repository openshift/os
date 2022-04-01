FROM registry.ci.openshift.org/ocp/builder:rhel-8-golang-1.17-openshift-4.10 AS builder
WORKDIR /go/src/github.com/openshift/os
COPY . .
# Prevent go mod from requiring a vendor directory.
ENV GOFLAGS=-mod=mod
# Compile our layering test binary for future use.
RUN go test -v -c -o layering_test ./tests/layering

FROM registry.svc.ci.openshift.org/coreos/coreos-assembler:latest
WORKDIR /src
COPY --from=builder /go/src/github.com/openshift/os/layering_test /usr/local/bin/layering_test
COPY . .
