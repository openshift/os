## Downloads the extensions given the extensions.yaml
FROM registry.ci.openshift.org/rhcos-devel/rhel-coreos:latest as os
# Expects os to be cloned and this build run from the top level dir like:
# podman build -f extensions/Dockerfile .
# also expects submodules to be initialized
RUN mkdir /os
WORKDIR /os
ADD . .
ARG OPENSHIFT_CI=0
RUN --mount=type=secret,id=yumrepos,target=/os/secret.repo extensions/build.sh

## Creates the repo metadata for the extensions.
## This uses Fedora as a lowest-common-denominator because it will work on
## current p8/s390x. See https://github.com/openshift/os/issues/1000
FROM quay.io/fedora/fedora:41 as builder
COPY --from=os /usr/share/rpm-ostree/extensions/ /usr/share/rpm-ostree/extensions/
RUN rm -f /etc/yum.repos.d/*.repo \
&& curl -L https://raw.githubusercontent.com/coreos/fedora-coreos-config/testing-devel/fedora-archive.repo -o /etc/yum.repos.d/fedora-archive.repo
RUN dnf install -y createrepo_c
RUN createrepo_c /usr/share/rpm-ostree/extensions/

# Generate extensions.json for meta.json.
# Use dnf repoquery to print 'name: version,' for each RPM
# sed to remove the comma from the last RPM
RUN (echo "{" && \
(dnf repoquery --repofrompath=extensions,/usr/share/rpm-ostree/extensions/ \
  --quiet --disablerepo=* --enablerepo=extensions \
  --queryformat "\"%{name}\": \"%{evr}.%{arch}\"," | \
sed "$ s/,$//") && echo "}") >> /usr/share/rpm-ostree/extensions.json

## Final container that has the extensions repo dir
FROM registry.access.redhat.com/ubi9/ubi:latest
COPY --from=builder /usr/share/rpm-ostree/extensions/ /usr/share/rpm-ostree/extensions/
# Make this the last layer, this is similar to the metalayer trick in the node
# image, but this one is specific to rpm-ostree extensions.
COPY --from=builder /usr/share/rpm-ostree/extensions.json /usr/share/rpm-ostree/extensions.json
