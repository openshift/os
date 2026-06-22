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
    awk "/\[.*\]/{p=0} /\[rhel-9.8-server-ose-4.22\]/{p=1} p" /etc/yum.repos.d/*.repo > /etc/yum.repos.d/okd.repo.tmp
    sed -i -e 's,\[rhel-9.8-server-ose-4.22\],\[rhel-9.8-server-ose-4.22-okd\],' /etc/yum.repos.d/okd.repo.tmp
    echo 'includepkgs=openshift-*,ose-aws-ecr-*,ose-azure-acr-*,ose-gcp-gcr-*,ose-crio-* ' >> /etc/yum.repos.d/okd.repo.tmp
    mv /etc/yum.repos.d/okd.repo{.tmp,}
fi

# XXX: patch cri-o spec to use tmpfiles
# https://github.com/CentOS/centos-bootc/issues/393
mkdir -p /var/opt

# this is where all the real work happens
rpm-ostree experimental compose treefile-apply \
    --var "osversion=${ID}-${VERSION_ID}" /run/src/packages-openshift.yaml

# --- DNM / PoC (coreos/afterburn#1251): replace afterburn with a prebuilt el9 RPM of
# afterburn main, which includes "kubevirt: Support static gateway and DNS with DHCP".
# (The @CoreOS/continuous COPR EL9/EL10 builds are currently broken, so the RPM is
# vendored in this PR and bind-mounted at /run/src.) `override replace` swaps the base
# afterburn, and the compose regenerates the initramfs, so the patched binary lands in
# the initrd where afterburn-network-kargs runs. x86_64-only PoC.
if [ "$(uname -m)" = x86_64 ]; then
    rpm-ostree override replace /run/src/afterburn-5.11.0-0.dev.pr1251.el9.x86_64.rpm
fi

# cleanup any repo files we injected
rm -f /etc/yum.repos.d/{ocp,git,okd}.repo

find /usr -name '*.pyc.bak' -exec sh -c 'mv $1 ${1%.bak}' _ {} \;
ostree container commit
