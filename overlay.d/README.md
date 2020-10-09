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
