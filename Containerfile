# This builds the final OCP/OKD node image on top of the base CoreOS image. For
# instructions on how to build this, see `docs/building.md`.

FROM quay.io/openshift-release-dev/ocp-v4.0-art-dev:c10s-coreos as build
ARG OPENSHIFT_CI=0
RUN --mount=type=bind,target=/run/src --mount=type=secret,id=yumrepos,target=/etc/yum.repos.d/secret.repo /run/src/build-node-image.sh

FROM build as metadata
RUN --mount=type=bind,target=/run/src /run/src/scripts/generate-metadata

FROM build
COPY --from=metadata /usr/share/openshift /usr/share/openshift
LABEL io.openshift.metalayer=true
