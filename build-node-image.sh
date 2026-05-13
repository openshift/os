#!/bin/bash
set -euxo pipefail

# This script builds the OpenShift node image. It's called from `Containerfile`.

# Avoid shipping modified .pyc files. Due to
# https://github.com/ostreedev/ostree/issues/1469, any Python apps that
# run (e.g. dnf) will cause pyc creation. We do this by backing them up and
# restoring them at the end.
find /usr -name '*.pyc' -exec mv {} {}.bak \;

# fetch repos from in-cluster mirrors if we're running in OpenShift CI
if [ "${OPENSHIFT_CI}" != 0 ]; then
    /run/src/ci/get-ocp-repo.sh /etc/yum.repos.d/ocp.repo
fi

# add all the repos from the src repo into `/etc/yum.repos.d` so dnf sees them
cat /run/src/*.repo >> /etc/yum.repos.d/git.repo

source /etc/os-release

# XXX: For SCOS, only allow certain packages to come from ART; everything else
# should come from CentOS. We should eventually sever this.
if [ $ID = centos ]; then
    # this says: "if the line starts with [.*], turn off printing. if the line starts with [our-repo], turn it on."
    awk "/\[.*\]/{p=0} /\[rhel-10.2-server-ose\]/{p=1} p" /etc/yum.repos.d/*.repo > /etc/yum.repos.d/okd.repo.tmp
    sed -i -e 's,\[rhel-10.2-server-ose\],\[rhel-10.2-server-ose-5.0-okd\],' /etc/yum.repos.d/okd.repo.tmp
    echo 'includepkgs=openshift-*,ose-aws-ecr-*,ose-azure-acr-*,ose-gcp-gcr-*,ose-crio-* ' >> /etc/yum.repos.d/okd.repo.tmp
    mv /etc/yum.repos.d/okd.repo{.tmp,}
fi

# XXX: patch cri-o spec to use tmpfiles
# https://github.com/CentOS/centos-bootc/issues/393
mkdir -p /var/opt

# Disable repos that don't match the current OS version to avoid 401 errors
# when rpm-ostree tries to access all repos. This replicates the conditional-include
# logic that was previously in packages-openshift.yaml.
if [ "$ID" = "rhel" ]; then
    if [ "$VERSION_ID" = "9.8" ]; then
        # Disable rhel-10.2 and centos repos for rhel-9.8 builds
        for repo in /etc/yum.repos.d/{ocp,git,secret}.repo; do
            [ -f "$repo" ] && sed -i -E '/^\[(rhel-10\.2|c10s)/,/^$/s/^enabled=1$/enabled=0/g' "$repo"
        done
    elif [ "$VERSION_ID" = "10.2" ]; then
        # Disable rhel-9 and centos repos for rhel-10.2 builds
        for repo in /etc/yum.repos.d/{ocp,git,secret}.repo; do
            [ -f "$repo" ] && sed -i -E '/^\[(rhel-9|c10s)/,/^$/s/^enabled=1$/enabled=0/g' "$repo"
        done
    fi
elif [ "$ID" = "centos" ] && [ "$VERSION_ID" = "10" ]; then
    # Disable rhel repos for centos-10 builds
    for repo in /etc/yum.repos.d/{ocp,git,secret}.repo; do
        [ -f "$repo" ] && sed -i -E '/^\[rhel-/,/^$/s/^enabled=1$/enabled=0/g' "$repo"
    done
fi

# Install the OCP packages. Repos have been configured above.
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
# These were previously in the `postprocess` section of packages-openshift.yaml.

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
cat >> /usr/lib/os-release <<EOF
OPENSHIFT_VERSION="5.0"
EOF

# Generate MOTD
. /etc/os-release
# Detect variant based on the Containerfile metadata. In the absence of
# rpm-ostree treefile metadata, we use a heuristic: centos-10 builds are SCOS.
if [ "$ID" = "centos" ] && [ "$VERSION_ID" = "10" ]; then
    colloquial_name=SCOS
    project_name=OKD
else
    colloquial_name=RHCOS
    project_name=OpenShift
fi
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

# cleanup any repo files we injected
rm -f /etc/yum.repos.d/{ocp,git,okd}.repo

find /usr -name '*.pyc.bak' -exec sh -c 'mv $1 ${1%.bak}' _ {} \;
ostree container commit
