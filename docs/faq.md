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

## Q: Where should I report issues with OpenShift Container Platform or Red Hat CoreOS?

OpenShift Container Platform (OCP) and Red Hat CoreOS (RHCOS) are products from Red Hat that customers can receive support for. If you encounter an issue with either OCP or RHCOS, you can use the [official support options](https://access.redhat.com/support) or [file a Bugzilla report](https://bugzilla.redhat.com/enter_bug.cgi?product=OpenShift%20Container%20Platform) about your issue.

[OKD](https://www.okd.io/) is the community distribution of Kubernetes that powers OpenShift. If you have issues with OKD, you should report the issue on the [upstream issue tracker](https://github.com/openshift/okd).  (Please note that using RHCOS with OKD is not supported.)

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

## Q: How do I know which RHEL will be in the next release?

RHEL CoreOS ships RHEL updates after they're released.  At the time of this writing, OpenShift 4.6 and below will stay on RHEL 8.2 EUS, and OpenShift 4.7 will (soon) start tracking RHEL 8.3.

## Q: How do I determine what version of an RPM is included in an RHCOS release?

The contents of each RHCOS release are visible in the [release browser](https://releases-rhcos-art.cloud.privileged.psi.redhat.com/) via the "OS contents" link next to each build.

Alternately, you can query the metadata directly:

```
$ curl -Ls https://releases-rhcos-art.cloud.privileged.psi.redhat.com/storage/releases/rhcos-4.5/45.82.202007140205-0/x86_64/commitmeta.json | jq '.["rpmostree.rpmdb.pkglist"][] | select(.[0] == "cri-o")'
[
  "cri-o",
  "0",
  "1.18.2",
  "18.rhaos4.5.git754d46b.el8",
  "x86_64"
]
```

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

## Q: Why are there no yum (rpm-md) repositories in /etc/yum.repos.d?

First, a core part of the design is that the OS upgrades are controlled
by and integrated with the cluster.  See [OSUpgrades.md](https://github.com/openshift/machine-config-operator/blob/master/docs/OSUpgrades.md).

A key part of the idea here with OpenShift 4 is that everything around
our continuous integration and delivery pipeline revolves around the release image.
The state of the installed system can be derived by that checksum; there
aren't other external inputs that need to be mirrored or managed.

Further, you only need a regular container pull secret to be able to
download and mirror OpenShift 4, including the operating system updates.
There is no `subscription-manager` step required.

Conceptually, RPMs are an implementation detail.

For these reasons, RHCOS does not include any rpm-md (yum) repository
configuration in `/etc/yum.repos.d`.

## Q: How do I build my own version of RHCOS for testing?

See the [development doc](docs/development.md).

Also reference the docs from the `machine-config-operator` about
[hacking on the `machine-os-content`](https://github.com/openshift/machine-config-operator/blob/master/docs/HACKING.md#hacking-on-machine-os-content)
which is the container image that houses the OS content that RHCOS nodes upgrade to.

## Q: How do I get RHCOS in a private EC2 region?

I am using a non-default AWS region such as GovCloud or AWS China, and when I try to import the AMI I see:

`EFI partition detected. UEFI booting is not supported in EC2.`

As of OpenShift 4.3, RHCOS has a unified BIOS/UEFI partition layout. As such, it is not compatible with the default `aws ec2 import-image` API (for more information, see discussions in https://github.com/openshift/os/pull/396).

Instead, you must use `aws ec2 import-snapshot` combined with `aws ec2 register-image`. To learn more about these APIs, see the AWS documentation for [importing snapshots](https://docs.aws.amazon.com/vm-import/latest/userguide/vmimport-import-snapshot.html) and [creating EBS-backed AMIs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/creating-an-ami-ebs.html#creating-launching-ami-from-snapshot).

In the future the OpenShift installer will likely have support for this.

## Q: Can I use Driver Update Program disks with RHCOS?

No, there is no supported mechanism for non-default kernel modules at this time, which includes [driver disks](https://access.redhat.com/articles/64322).

## Q: How do I capture console logs from an RHCOS node running on vSphere?

It's possible to write the serial console data directly to the VMFS volume.  You can do this by changing the Virtual Hardware settings of the VM to include a serial port that writes to a file (see [screenshot](https://raw.githubusercontent.com/openshift/os/main/docs/vsphere-settings.png)).  The [official documetation](https://docs.vmware.com/en/VMware-vSphere/7.0/com.vmware.vsphere.vm_admin.doc/GUID-C6FBCF66-5796-4EE6-BF47-4DCAA9DCD1E3.html) from VMware has additional details.

Alternatively, you can try the [OpenStack VMWare Virtual Serial Port Concentrator container](https://github.com/jcpowermac/vmware-vspc-container).

## Q: How do I log into a node via console?

See https://access.redhat.com/solutions/5500131
The FCOS equivalent is https://docs.fedoraproject.org/en-US/fedora-coreos/access-recovery/

## Q: Does RHCOS support multipath?

Yes. Multipath is turned on at installation time by using:

```
coreos-installer install --append-karg rd.multipath=default --append-karg root=/dev/disk/by-label/dm-mpath-root ...
```

If your environment permits it, it's also possible to turn on multipath as a day-2 operation using a MachineConfig object which appends the same kernel arguments. Note however that in some setups, any I/O to non-optimized paths will result in I/O errors. And since there is no guarantee which path the host may select prior to turning on multipath, this may break the system. In these cases, you must enable multipathing at installation time.

Currently, non-default multipath configurations cannot be set at installation time. After booting with the default configuration, you may change the settings in `/etc/multipath.conf` just like on traditional RHEL (see docs [here](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/configuring_device_mapper_multipath/index)). If you need these customized settings to take effect from the initrd, then you will need to enable initramfs regeneration via `rpm-ostree initramfs --enable` and remove the `rd.multipath=default` kernel argument (e.g. `rpm-ostree kargs --delete rd.multipath=default`).

## Q: Does RHCOS support the use of `NetworkManager` keyfiles?  Does RHCOS support the use of `ifcfg` files?

Starting with RHCOS 4.6, it is possible to use either `NetworkManager` keyfiles or `ifcfg` files for configuring host networking.  It is strongly preferred to use `NetworkManager` keyfiles.
