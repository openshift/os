# This builds the final OCP/OKD node image on top of the base CoreOS image. For
# instructions on how to build this, see `docs/building.md`.

FROM quay.io/openshift-release-dev/ocp-v4.0-art-dev:c9s-coreos as build
ARG OPENSHIFT_CI=0
RUN --mount=type=bind,target=/run/src --mount=type=secret,id=yumrepos,target=/etc/yum.repos.d/secret.repo /run/src/build-node-image.sh

FROM build as metadata
RUN --mount=type=bind,target=/run/src /run/src/scripts/generate-metadata

FROM build
COPY --from=metadata /usr/share/openshift /usr/share/openshift
LABEL io.openshift.metalayer=true
# Add a hack to get OpenShift tests working again because a
# revert of the new architecture happened in
# https://github.com/openshift/machine-config-operator/pull/5703
# because we can't add labels to the rhel-10.2 yet:
# https://github.com/coreos/rhel-coreos-config/blob/1ba124d37b93a095bb5ec2ef5b421965b982b255/build-args-rhel-10.2.conf#L15-L18
LABEL ostree.linux=true
