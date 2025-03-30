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

FROM quay.io/openshift-release-dev/ocp-v4.0-art-dev:c9s-coreos as build
ARG OPENSHIFT_CI=0
RUN --mount=type=bind,target=/run/src --mount=type=secret,id=yumrepos,target=/etc/yum.repos.d/secret.repo <<EOF
    set -xeuo pipefail

    # Avoid shipping modified .pyc files. Due to
    # https://github.com/ostreedev/ostree/issues/1469, any Python apps that
    # run (e.g. dnf) will cause pyc creation. We do this by backing them up and
    # restoring them at the end.
    find /usr -name '*.pyc' -exec mv {} {}.bak \;

    # fetch repos from in-cluster mirrors if we're running in OpenShift CI
    if [ "${OPENSHIFT_CI}" != 0 ]; then
        /run/src/ci/get-ocp-repo.sh --ocp-layer /run/src/packages-openshift.yaml --output-dir /etc/yum.repos.d
    fi

    # XXX: patch cri-o spec to use tmpfiles
    # https://github.com/CentOS/centos-bootc/issues/393
    mkdir -p /var/opt

    source /etc/os-release
    # this is where all the real work happens
    rpm-ostree experimental compose treefile-apply \
        --var id=$ID /run/src/packages-openshift.yaml

    # do any cleanups necessary to undo what `get-ocp-repo.sh` did
    if [ "${OPENSHIFT_CI}" != 0 ]; then
        /run/src/ci/get-ocp-repo.sh --output-dir /etc/yum.repos.d --cleanup
    fi

    find /usr -name '*.pyc.bak' -exec sh -c 'mv $1 ${1%.bak}' _ {} \;
    ostree container commit
EOF

FROM build as metadata
RUN --mount=type=bind,target=/run/src /run/src/scripts/generate-metadata

FROM build
COPY --from=metadata /usr/share/openshift /usr/share/openshift
LABEL io.openshift.metalayer=true
