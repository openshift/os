# Questions and answers

The goal of this file is to have a place to easily commit answers to questions
in a way that's easily searchable, and can make its way into official
documentation later.

## Q: How do I provide static IP addresses?

As of OpenShift 4.2, by default the kernel command line arguments for networking
are persisted.  See this PR: https://github.com/coreos/ignition-dracut/pull/89

In cases where you want to have the first boot use DHCP, but subsequent boots
use a different static configuration, you can write the traditional Red Hat Linux
`/etc/sysconfig/network-scripts` files, or NetworkManager configuration files, and
include them in Ignition.

The MCO does not have good support for "per-node" configuration today, but
in the future when it does, writing this as a MachineConfig fragment
passed to the installer will make sense too.

## Q: How does networking differ between Fedora CoreOS and RHCOS?

The biggest is that Fedora CoreOS does not ship the `ifcfg` (initscripts) plugin to
NetworkManager.  In contrast, RHEL is committed to long term support for initscripts
to maximize compatibility.

The other bit is related to the above - RHCOS has [code to propagate
kernel commandline arguments](https://github.com/coreos/ignition-dracut/pull/89) to ifcfg files, FCOS doesn't have an equivalent
of this for NetworkManager config files.
