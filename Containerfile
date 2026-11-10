# This builds the final OCP node image on top of the base RHCOS image. The
# latter may be RHEL or CentOS Stream-based. This is currently only buildable
# using podman/buildah as it uses some mounting options only available there.
#
# To build this, you will want to pass `--security-opt=label=disable` (or
# relabel the context directory). To inject additional yum repos, use `--secret
# id=yumrepos,src=/path/to/my.repo`.
#
# Use `--from` to override the base RHCOS image. E.g.:
#
# podman build --from quay.io/openshift-release-dev/ocp-v4.0-art-dev:rhel-coreos-base-9.6 ...
#
# Or to use a locally built OCI archive:
#
# podman build --from oci-archive:builds/latest/x86_64/scos-9-20240416.dev.0-ostree.x86_64.ociarchive ...

# If consuming from repos hosted within the RH network, you'll want to mount in
# certs too:
#
# podman build -v /etc/pki/ca-trust:/etc/pki-ca-trust:ro ...
#
# Example invocation:
#
# podman build --from oci-archive:$(ls builds/latest/x86_64/*.ociarchive) \
#   --secret id=yumrepos,src=$PWD/src/yumrepos/rhel-9.6.repo \
#   -v /etc/pki/ca-trust:/etc/pki/ca-trust:ro \
#   --security-opt label=disable -t localhost/openshift-node-c9s \
#   src/config
#
# Prefer `--build-arg-file build-args-4.19-*.conf` for variant metadata
# (IMAGE_FROM, STREAM_CLASS, and RHEL IMAGE_NAME/IMAGE_CPE).

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
COPY --from=metadata /usr/share/buildinfo /usr/share/buildinfo
# Copy in the meta.json. This needs to be the last operation that
# creates a layer in the image build so that our `oc image extract img[-1]`
# trick works. See https://github.com/coreos/fedora-coreos-pipeline/blob/80c2625b89185f8adc5568fae112484a427c5806/utils.groovy#L1004
COPY --from=metadata /usr/share/openshift /usr/share/openshift
ARG IMAGE_NAME
ARG IMAGE_CPE
ARG TARGETARCH
ARG STREAM_CLASS
LABEL name=${IMAGE_NAME}
LABEL cpe=${IMAGE_CPE}
LABEL architecture=${TARGETARCH}
LABEL io.openshift.metalayer=true
LABEL io.openshift.os.streamclass=${STREAM_CLASS}
