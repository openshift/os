# Questions and answers

The goal of this file is to have a place to easily commit answers to questions
in a way that's easily searchable, and can make its way into official
documentation later.

## Q: What is CoreOS?

You may have been linked to this FAQ because you used the term "CoreOS".
This can be a few things.

There's the original Container Linux that started from http://coreos.com/ (also a company RHT acquired)

More recently, there are two successors to Container Linux (original CoreOS)

 - [Fedora CoreOS](https://getfedora.org/coreos/)
 - [Red Hat Enterprise Linux CoreOS](https://docs.openshift.com/container-platform/latest/architecture/architecture-rhcos.html), a part of OpenShift 4

It's generally preferred that instead of saying "CoreOS", to explicitly
use one of the shorter forms "FCOS" (for Fedora CoreOS) or "RHCOS" for RHEL CoreOS.

FCOS and RHCOS share [Ignition](https://github.com/coreos/ignition) and [rpm-ostree](https://github.com/coreos/rpm-ostree/)
as key technologies.

Fedora CoreOS also acts as one upstream for RHEL CoreOS, although
RHEL CoreOS uses RHEL content.

We use these terms because e.g. RHEL CoreOS *is* Red Hat Enterprise Linux, more than it's not.
It inherits most of the content, such as the kernel and a number of the same certifications.
However, it differs in how it's managed - RHEL CoreOS is managed by the
[machine config operator](https://github.com/openshift/machine-config-operator/).

Similarly, Fedora CoreOS is an "edition" of Fedora.

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

## Q: How do I upgrade the OS?

OS upgrades are integrated with cluster upgrades; so you `oc adm upgrade`, use
the console etc.  See also https://github.com/openshift/machine-config-operator/blob/master/docs/OSUpgrades.md

However, if you're a developer/tester and want to try something different; see
this document https://github.com/openshift/machine-config-operator/blob/master/docs/HACKING.md#hacking-on-machine-os-content

For example, to directly switch to the `machine-os-content` from a release image like
https://openshift-release.svc.ci.openshift.org/releasestream/4.2.0-0.nightly/release/4.2.0-0.nightly-2019-11-06-011942
You could do:

```
$ oc adm release info --image-for=machine-os-content  quay.io/openshift-release-dev/ocp-release:4.2.10
quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:02d810d3eb284e684bd20d342af3a800e955cccf0bb55e23ee0b434956221bdd
$ pivot quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:02d810d3eb284e684bd20d342af3a800e955cccf0bb55e23ee0b434956221bdd
```

## Q: How do I see which RHEL and RHCOS version is in a release?

Like above, but add `oc image info`:

```
$ oc image info $(oc adm release info --image-for=machine-os-content quay.io/openshift-release-dev/ocp-release:4.2.10)
...
Labels:     com.coreos.ostree-commit=33dd81479490fbb61a58af8525a71934e7545b9ed72d846d3e32a3f33f6fac9d
            version=42.81.20191203.0
```

Here the `81` means it's using RHEL 8.1.

## Q: How do I debug Ignition failures?

Today, when Ignition fails, it will wait in an "emergency shell" for 5 minutes.
The intention is to avoid "partially provisioned" systems.  To debug things,
here are a few tips and tricks.

In the emergency shell, you can use `systemctl --failed` to show units which failed.
From there, `journalctl -b -u <unit>` may help - for example, `journalctl -b -u ignition-files.service`.

Usually, you'll have networking in the initramfs, so you can also use e.g. `curl` to extract data.
See for example [this StackExchange question](https://unix.stackexchange.com/a/108495).

See also https://github.com/coreos/ignition/issues/585

## Q: What happens when I use `rpm-ostree override replace` to replace an RPM?

When a package is replaced in this fashion, it will remain in place through any subsequent upgrades.

While this can be helpful for short-term fixes, it is important to remember that the package replacement
is in place, as the cluster currently has [no mechanism for reporting](https://github.com/openshift/machine-config-operator/issues/945) that the node has been changed in this
fashion.  This kind of package replacement can also leave your nodes exposed to potential problems
that are fixed in newer versions of the package.

## Q: How do I build my own version of RHCOS for testing?

You need the RHCOS manifest configuration (currently hosted on an RHT internal [GitLab repo](https://url.corp.redhat.com/rhcos-repo)) and
[coreos-assembler](https://github.com/coreos/coreos-assembler).

If you want to replace particular binaries or RPMs in RHCOS, the `coreos-assembler` has
[override mechanisms](https://github.com/coreos/coreos-assembler/blob/master/README-devel.md#using-overrides)
to do this.

Also reference the docs from the `machine-config-operator` about
[hacking on the `machine-os-content`](https://github.com/openshift/machine-config-operator/blob/master/docs/HACKING.md#hacking-on-machine-os-content)
which is the container image that houses the OS content that RHCOS nodes upgrade to.

## Q: How do I get RHCOS in a private EC2 region?

I am using a non-default AWS region such as GovCloud or AWS China, and when I try to import the AMI I see:

`EFI partition detected. UEFI booting is not supported in EC2.`

As of OpenShift 4.3, RHCOS has a unified BIOS/UEFI partition layout. As such, it is not compatible with the default `aws ec2 import-image` API (for more information, see discussions in https://github.com/openshift/os/pull/396).

Instead, you must use `aws ec2 import-snapshot` combined with `aws ec2 register-image`. To learn more about these APIs, see the AWS documentation for [importing snapshots](https://docs.aws.amazon.com/vm-import/latest/userguide/vmimport-import-snapshot.html) and [creating EBS-backed AMIs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/creating-an-ami-ebs.html#creating-launching-ami-from-snapshot).

In the future the OpenShift installer will likely have support for this.
