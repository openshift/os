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
