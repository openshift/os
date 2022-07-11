#Build a newer rpm-ostree
FROM quay.io/centos/centos:stream8 as rpm-ostree
RUN sed -i -e 's,enabled=0,enabled=1,' /etc/yum.repos.d/CentOS-Stream-PowerTools.repo
RUN yum -y group install "Development Tools"

RUN git clone https://github.com/coreos/rpm-ostree.git
WORKDIR rpm-ostree
RUN git checkout rhel8
RUN ./ci/installdeps.sh
RUN PATH=$PATH:/rpm-ostree/target/cxxbridge/bin/
RUN git submodule update --init
RUN env CFLAGS='-ggdb -Og' CXXFLAGS='-ggdb -Og' ./autogen.sh --prefix=/usr --libdir=/usr/lib64 --sysconfdir=/etc
RUN make

## Downloads the extensions given the extensions.yaml
FROM registry.ci.openshift.org/rhcos-devel/rhel-coreos:latest as os

# Install new rpm-ostree
COPY --from=rpm-ostree /rpm-ostree/target/debug/rpm-ostree /usr/bin/rpm-ostree

# Expects os to be cloned and this build run from the top level dir like:
# podman build -f extensions/Dockerfile .
# also expects submodules to be initialized
RUN mkdir /os
WORKDIR /os
ADD . .
RUN if [ ! -f ocp.repo  ]; then ci/get-ocp-repo.sh ; fi

RUN rpm-ostree compose extensions --rootfs=/ --output-dir=/usr/share/rpm-ostree/extensions/ {manifest,extensions}.yaml

## Creates the repo metadata for the extensions & builds the go binary
FROM quay.io/centos/centos:stream8 as builder
COPY --from=os /usr/share/rpm-ostree/extensions/ /usr/share/rpm-ostree/extensions/
RUN dnf install -y createrepo_c golang
ADD extensions/repo-server/main.go .
RUN mkdir /build
RUN go build -o /build/webserver main.go

RUN createrepo_c /usr/share/rpm-ostree/extensions/

## Final container that has the extensions and webserver
FROM registry.access.redhat.com/ubi8/ubi:latest
COPY --from=builder /build/webserver /usr/bin/webserver
COPY --from=builder /usr/share/rpm-ostree/extensions/ /usr/share/rpm-ostree/extensions/

CMD ["./usr/bin/webserver"]
EXPOSE 9091/tcp
