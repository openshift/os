# This line is interpreted by coreos-virt-install
#--coreos-virt-install-disk-size-gb: 8
%include image-base.ks
# Not the default in EL7
auth --useshadow --passalgo=sha512
ostreesetup --nogpg --osname=rhcos --remote=rhcos --url=@@OSTREE_INSTALL_URL@@ --ref=openshift/3.10/x86_64/os
