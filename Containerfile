# Base image from OpenShift release for the OCP node build
# This base image is typically RHEL or CentOS Stream-based
# It's buildable with podman or buildah only, using mounting options available only there.
#
# To build this, use `--security-opt=label=disable` to avoid relabeling the context directory.
# Any repos found in `/run/yum.repos.d` will be imported to `/etc/yum.repos.d/` and removed.
#
# Override the base RHCOS image with --from. Example:
# podman build --from quay.io/openshift-release-dev/ocp-v4.0-art-dev:rhel-coreos-base-9.4 ...

# Use local OCI archive as base:
# podman build --from oci-archive:builds/latest/x86_64/scos-9-20240416.dev.0-ostree.x86_64.ociarchive ...

# If consuming from RH network repos, mount certs:
# podman build -v /etc/pki/ca-trust:/etc/pki-ca-trust:ro ...

# Example invocation:
# podman build --from oci-archive:$(ls builds/latest/x86_64/*.ociarchive) \
#   -v rhel-9.4.repo:/run/yum.repos.d/rhel-9.4.repo:ro \
#   -v /etc/pki/ca-trust:/etc/pki/ca-trust:ro \
#   --security-opt label=disable -t localhost/openshift-node-c9s src/config

# Set base image for OpenShift node build
FROM quay.io/openshift-release-dev/ocp-v4.0-art-dev:c9s-coreos

# Argument to control OpenShift CI behavior
ARG OPENSHIFT_CI=0

# Avoid shipping modified .pyc files caused by Python apps (e.g., dnf)
# As of https://github.com/ostreedev/ostree/issues/1469, pyc creation happens during certain app executions

# Clean .pyc files, apply OCP repo, and remove the repos after importing
RUN --mount=type=bind,target=/run/src \
  # Step 1: Remove existing .pyc files to avoid shipping modified ones
  find /usr -name '*.pyc' -exec mv {} {}.bak \; && \
  
  # Step 2: If OpenShift CI is enabled, fetch the OCP repo and apply the manifest
  if [ "${OPENSHIFT_CI}" != 0 ]; then \
    /run/src/ci/get-ocp-repo.sh --ocp-layer /run/src/packages-openshift.yaml --output-dir /run/yum.repos.d; \
  fi && \
  
  # Step 3: Apply the manifest to the system
  /run/src/scripts/apply-manifest /run/src/packages-openshift.yaml && \
  
  # Step 4: Restore .pyc files (removes .bak extension)
  find /usr -name '*.pyc.bak' -exec sh -c 'mv $1 ${1%.bak}' _ {} \; && \
  
  # Step 5: Commit the container with optimizations
  ostree container commit

# Commit message for container optimization:
# Optimized OCP node build by cleaning up Python bytecode files, applying OCP repo, and restoring original files.
