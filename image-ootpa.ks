# This line is interpreted by coreos-virt-install
#--coreos-virt-install-disk-size-gb: 8
%include image-base.ks
ostreesetup --nogpg --osname=rhcos --remote=rhcos --url=@@OSTREE_INSTALL_URL@@ --ref=openshift/4/x86_64/os-ootpa
