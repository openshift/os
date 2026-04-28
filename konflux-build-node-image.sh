#!/bin/bash
set -euxo pipefail

# This script builds the OpenShift node image for Konflux builds.
# It's called from `Containerfile.konflux`.
#
# Unlike `build-node-image.sh` (which uses rpm-ostree treefile-apply with
# packages-openshift.yaml), this script uses direct rpm-ostree install and
# embeds all postprocess steps inline. This keeps the Konflux build path
# fully independent of the existing CI/Jenkins build path.
#
# See also: https://github.com/openshift/os/pull/1929

# Avoid shipping modified .pyc files. Due to
# https://github.com/ostreedev/ostree/issues/1469, any Python apps that
# run (e.g. dnf) will cause pyc creation. We do this by backing them up and
# restoring them at the end.
find /usr -name '*.pyc' -exec mv {} {}.bak \;

# Install the OCP packages. Repos are expected to be injected via
# Konflux secrets/mounts in the Containerfile.
rpm-ostree install \
    cri-o cri-tools conmon-rs \
    openshift-clients openshift-kubelet \
    openvswitch3.5 \
    NetworkManager-ovs \
    ose-aws-ecr-image-credential-provider \
    ose-azure-acr-image-credential-provider \
    ose-gcp-gcr-image-credential-provider \
    ose-crio-credential-provider

# --- postprocess steps ---
# These are migrated from the `postprocess` section of packages-openshift.yaml.
# They must run after package installation.

# Disable any built-in repos. We need to work in disconnected environments by
# default, and default-enabled repos will be attempted to be fetched by
# rpm-ostree when doing node-local kernel overrides today for e.g. kernel-rt.
mkdir -p /etc/yum.repos.d
for x in $(find /etc/yum.repos.d/ -name '*.repo'); do
    # ignore repo files that are mountpoints since they're likely secrets
    if ! mountpoint "$x"; then
        sed -i -e 's/enabled\s*=\s*1/enabled=0/g' "$x"
    fi
done

# Enable librhsm which enables host subscriptions to work in containers
# https://github.com/rpm-software-management/librhsm/blob/fcd972cbe7c8a3907ba9f091cd082b1090231492/rhsm/rhsm-context.c#L30
ln -sr /run/secrets/etc-pki-entitlement /etc/pki/entitlement-host
ln -sr /run/secrets/rhsm /etc/rhsm-host

# Manually modify SELinux booleans that are needed for OCP use cases
semanage boolean --modify --on container_use_cephfs      # RHBZ#1694045
semanage boolean --modify --on virt_use_samba            # RHBZ#1754825

# https://gitlab.cee.redhat.com/coreos/redhat-coreos/merge_requests/812
# https://bugzilla.redhat.com/show_bug.cgi?id=1796537
mkdir -p /usr/share/containers/oci/hooks.d

# crio conmon symlink
mkdir -p /usr/libexec/crio
ln -sr /usr/bin/conmon /usr/libexec/crio/conmon

# Inject OpenShift-specific release fields
# NOTE: The OCP version here should be kept in sync with the version used
# in the branch-specific packages-openshift.yaml. For master, we use
# the latest version.
cat >> /usr/lib/os-release <<EOF
OPENSHIFT_VERSION="4.22"
EOF

# Generate MOTD
. /etc/os-release
# For Konflux RHCOS builds, we always use the RHCOS variant
colloquial_name=RHCOS
project_name=OpenShift
# in the el-only variants, we already have CoreOS in the NAME, so don't
# re-add it when building the node image
if [[ $NAME != *CoreOS* ]]; then
    NAME="$NAME CoreOS"
fi
cat > /etc/motd <<EOF
$NAME $OSTREE_VERSION
  Part of ${project_name} ${OPENSHIFT_VERSION}, ${colloquial_name} is a Kubernetes-native operating system
  managed by the Machine Config Operator (\`clusteroperator/machine-config\`).

WARNING: Direct SSH access to machines is not recommended; instead,
make configuration changes via \`machineconfig\` objects:
  https://docs.openshift.com/container-platform/${OPENSHIFT_VERSION}/architecture/architecture-rhcos.html

---
EOF

# Delete leftover files in the layering path
if [ -f /run/.containerenv ]; then
    # lockfiles and backup files
    rm -f /etc/.pwd.lock /etc/group- /etc/gshadow- /etc/shadow- /etc/passwd-
    rm -f /etc/selinux/targeted/*.LOCK
    # cache, logs, etc...
    rm -rf /var && mkdir /var
    # All the entries here should instead be part of their respective
    # packages. But we carry them here for now to maintain compatibility.
    cat > /usr/lib/tmpfiles.d/openshift.conf << EOF
L /opt/cni - - - - ../../usr/lib/opt/cni
d /var/lib/cni 0755 root root - -
d /var/lib/cni/bin 0755 root root - -
d /var/lib/containers 0755 root root - -
d /var/lib/openvswitch 0755 root root - -
d /var/lib/openvswitch/pki 0755 root root - -
d /var/log/openvswitch 0750 openvswitch hugetlbfs - -
d /var/lib/unbound 0755 unbound unbound - -
EOF
fi

# --- end postprocess steps ---

# Cleanup any repo files we injected
rm -f /etc/yum.repos.d/{ocp,git,okd,secret}.repo

# Restore .pyc files
find /usr -name '*.pyc.bak' -exec sh -c 'mv $1 ${1%.bak}' _ {} \;

# Commit the ostree changes
ostree container commit
