# This builds the final OCP node image on top of the base RHCOS image. The
# latter may be RHEL or CentOS Stream-based. This is currently only buildable
# using podman/buildah as it uses some mounting options only available there.
#
# To build this, you will want to pass `--security-opt=label=disable` to avoid
# having to relabel the context directory. Any repos found in `/run/yum.repos.d`
# will be imported into `/etc/yum.repos.d/` and then removed in the same step (so
# as to not end up in the final image).
#
# Use `--from` to override the base RHCOS image. E.g.:
#
# podman build --from quay.io/openshift-release-dev/ocp-v4.0-art-dev:rhel-coreos-base-9.4 ...
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
#   -v rhel-9.4.repo:/run/yum.repos.d/rhel-9.4.repo:ro \
#   -v /etc/pki/ca-trust:/etc/pki/ca-trust:ro \
#   --security-opt label=disable -t localhost/openshift-node-c9s \
#   src/config

FROM quay.io/openshift-release-dev/ocp-v4.0-art-dev:c9s-coreos
ARG OPENSHIFT_CI=
RUN --mount=type=bind,target=/run/src \
  if [ -n "${OPENSHIFT_CI:-}" ]; then /run/src/ci/get-ocp-repo.sh --ocp-layer /run/src/packages-openshift.yaml; fi && \
  /run/src/scripts/apply-manifest /run/src/packages-openshift.yaml && \
  ostree container commit
