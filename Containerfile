# This builds the final OCP/OKD node image on top of the base CoreOS image. For
# instructions on how to build this, see `docs/building.md`.

ARG IMAGE_FROM=overridden
FROM ${IMAGE_FROM} as build
ARG OPENSHIFT_CI=0
RUN --mount=type=bind,target=/run/src --mount=type=secret,id=yumrepos,target=/etc/yum.repos.d/secret.repo /run/src/build-node-image.sh

FROM build as metadata
ARG IMAGE_NAME
ARG IMAGE_CPE
ARG TARGETARCH
RUN --mount=type=bind,target=/run/src /run/src/scripts/generate-metadata
RUN --mount=type=bind,target=/run/src /run/src/scripts/generate-labels

FROM build
COPY --from=metadata /usr/share/openshift /usr/share/openshift
COPY --from=metadata /usr/share/buildinfo /usr/share/buildinfo
ARG IMAGE_NAME
ARG IMAGE_CPE
ARG TARGETARCH
LABEL name=${IMAGE_NAME}
LABEL cpe=${IMAGE_CPE}
LABEL architecture=${TARGETARCH}
LABEL io.openshift.metalayer=true
# Add a hack to get OpenShift tests working again because a
# revert of the new architecture happened in
# https://github.com/openshift/machine-config-operator/pull/5703
# because we can't add labels to the rhel-10.2 yet:
# https://github.com/coreos/rhel-coreos-config/blob/1ba124d37b93a095bb5ec2ef5b421965b982b255/build-args-rhel-10.2.conf#L15-L18
LABEL ostree.linux=true
