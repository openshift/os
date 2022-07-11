# This file is consumed by the layering test. It is embedded into
# the layering test binary via an embed directive in the
# fixtures.go file.
ARG BASE_OS_IMAGE="registry.ci.openshift.org/rhcos-devel/rhel-coreos:latest"
FROM registry.access.redhat.com/ubi8/ubi:latest as builder
WORKDIR /build
COPY . .
RUN yum -y install go-toolset
RUN go build hello-world.go

FROM $BASE_OS_IMAGE
# Inject our Golang binary into our OS base image
COPY --from=builder /build/hello-world /usr/bin
# And add our unit file
ADD hello-world.service /etc/systemd/system/hello-world.service
RUN ostree container commit
