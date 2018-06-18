#!/bin/bash
#
# This stage builds packages from source repositories and
# creates dnf repos of the results
set -xeuo pipefail

echo "# Installing required packages"
dnf install -y git rsync openssh-clients dnf-plugins-core fedpkg dnf-utils awscli
cp $WORKSPACE/RPM-GPG-* /etc/pki/rpm-gpg/
dnf copr -y enable walters/buildtools-fedora
dnf install -y rpmdistro-gitoverlay

echo "# Cleaning/Setting up the environment"
rm -f rdgo.stamp
mkdir -p $RDGO
ln -sf $WORKSPACE/overlay.yml $RDGO/

echo "# Building"
cd $RDGO
rpmdistro-gitoverlay init
rpmdistro-gitoverlay resolve --fetch-all
rpmdistro-gitoverlay build --touch-if-changed $WORKSPACE/rdgo.stamp --logdir=$WORKSPACE/log
