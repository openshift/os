These overlay directories are automatically committed to the build OSTree repo
by coreos-assembler. They are then explicitly included in our various manifest
files via `ostree-layers` (this used to be done automatically, but that's no
longer the case).

01fcos
------

Import `05core` overlay from fedora-coreos-config

02fcos-nouveau
--------------

Blacklist the nouveau driver because it causes issues with some NVidia GPUs in
EC2, and we don't have a use case for FCOS with nouveau.

"Cannot boot an p3.2xlarge instance with RHCOS (g3.4xlarge is working)"
https://bugzilla.redhat.com/show_bug.cgi?id=1700056

05rhcos
-------

General RHCOS specific overlay.

15rhcos-tuned-bits
------------------

Real Time kernel support extracted from `tuned`.

21dhcp-chrony
-------------

Handle DHCP-provided NTP servers and configure chrony to use them,
without overwriting platform-specific configuration. Can be removed
once changes in upstream chrony with support for per-platform
defaults (https://bugzilla.redhat.com/show_bug.cgi?id=1828434),
and handling in 20-chrony and chrony-helper using the defaults
lands in downstream packages. See upstream thread:
https://listengine.tuxfamily.org/chrony.tuxfamily.org/chrony-dev/2020/05/msg00022.html

30rhcos-nvme-compat-udev
------------------------

NVMe by-id/ symlinks changed wrt leading spaces from RHEL8 to RHEL9:
https://issues.redhat.com/browse/OCPBUGS-11375
https://github.com/systemd/systemd/issues/27155

This overlay ships a rule that adds back the previous symlinks for backwards
compatibility. TBD when we can drop this, e.g. by having layered software use
the `eui` links instead or pivoting to GPT partition UUIDs. Customers may have
also manually typed the old symlink in their Ignition configs and other k8s
resources though. Those would require some communication before we can rip this
out.

30gcp-udev-rules
-------------------

Add udev rules and scripts needed from google-guest-configs [1] for disk
configuration in GCP, such as local SSD controllers (nvme and scsi).

The udev rules are also needed in the initramfs [2] and are delivered here via a dracut
module.

The google-compute-engine-guest-configs-udev package that exists in Fedora delivers
these files. We should drop this module when it exists in RHEL too.

[1] https://github.com/GoogleCloudPlatform/guest-configs/tree/master/src/lib/udev
[2] https://issues.redhat.com/browse/OCPBUGS-10942
[3] https://bugzilla.redhat.com/show_bug.cgi?id=2182865
