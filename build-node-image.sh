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
    awk "/\[.*\]/{p=0} /\[rhel-9.6-server-ose-4.21\]/{p=1} p" /etc/yum.repos.d/*.repo > /etc/yum.repos.d/okd.repo.tmp
    sed -i -e 's,\[rhel-9.6-server-ose-4.21\],\[rhel-9.6-server-ose-4.21-okd\],' /etc/yum.repos.d/okd.repo.tmp
    echo 'includepkgs=openshift-*,ose-aws-ecr-*,ose-azure-acr-*,ose-gcp-gcr-*' >> /etc/yum.repos.d/okd.repo.tmp
    mv /etc/yum.repos.d/okd.repo{.tmp,}
fi

# XXX: patch cri-o spec to use tmpfiles
# https://github.com/CentOS/centos-bootc/issues/393
mkdir -p /var/opt

# this is where all the real work happens
rpm-ostree experimental compose treefile-apply \
    --var "osversion=${ID}-${VERSION_ID}" /run/src/packages-openshift.yaml

# cleanup any repo files we injected
rm -f /etc/yum.repos.d/{ocp,git,okd}.repo

find /usr -name '*.pyc.bak' -exec sh -c 'mv $1 ${1%.bak}' _ {} \;
ostree container commit
