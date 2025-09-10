# Questions and answers

The goal of this file is to have a place to easily commit answers to questions
in a way that's easily searchable, and can make its way into official
documentation later.

## Q: What is CoreOS?

You may have been linked to this FAQ because you used the term "CoreOS".
This can be a few things.

There's the original Container Linux that started from <http://coreos.com/> (also a company RHT acquired)

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

OpenShift Container Platform (OCP) and Red Hat CoreOS (RHCOS) are products from Red Hat that customers can receive support for. If you encounter an issue with either OCP or RHCOS, you can use the [official support options](https://access.redhat.com/support) or [file a bug report](https://access.redhat.com/labs/rhir/) about your issue.

[OKD](https://www.okd.io/) is the community distribution of Kubernetes that powers OpenShift. If you have issues with OKD, you should report the issue on the [upstream issue tracker](https://github.com/openshift/okd).  (Please note that using RHCOS with OKD is not supported.)

## Q: How do I provide static IP addresses?

As of OpenShift 4.2, by default the kernel command line arguments for networking
are persisted.  See this PR: <https://github.com/coreos/ignition-dracut/pull/89>

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

## Q: How do I upgrade the OS manually or outside of a cluster?

By default, the operating system is upgraded [as part of cluster upgrades](https://docs.openshift.com/container-platform/4.12/updating/index.html).

For testing/development flows, the OS can be upgraded manually.  As of OpenShift 4.12+,
[OCP CoreOS Layering](https://docs.openshift.com/container-platform/4.12/post_installation_configuration/coreos-layering.html)
was implemented.  As part of this, a huge change is that the host code (rpm-ostree) can now directly pull and upgrade from a container image.

The doc says "Use the oc adm release info --image-for rhel-coreos-8 command to obtain the base image used in your cluster." so e.g.:

```
$ oc adm release info --image-for=rhel-coreos-8 quay.io/openshift-release-dev/ocp-release:4.12.4-x86_64
quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:329a8968765c2eca37d8cbd95ecab0400b5252a680eea9d279f41d7a8b4fdb93
```

Now, you can directly on a host system (which may not be joined to a cluster, just e.g. booted and provisioned with a SSH key),
write your [OpenShift pull secret](https://console.redhat.com/openshift/downloads#tool-pull-secret) to `/etc/ostree/auth.json`
(or `/run/ostree/auth.json`) - this step can be done via Ignition or manually.

Then, you can [rebase to the target image](https://coreos.github.io/rpm-ostree/container/#rebasing-a-client-system):

```
$ rpm-ostree rebase --experimental ostree-unverified-registry:quay.io/openshift-release-dev/ocp-v4.0-art-dev@sha256:329a8968765c2eca37d8cbd95ecab0400b5252a680eea9d279f41d7a8b4fdb93
```

This is particularly relevant because it's common for OCP/RHCOS to not publish new "bootimages" or disk images unless needed.

### Outside of release image pull specs

At the current time, these floating tags are available:

 - quay.io/openshift-release-dev/ocp-v4.0-art-dev:4.13-9.2
 - quay.io/openshift-release-dev/ocp-v4.0-art-dev:4.12

This may change in the future.

## Q: How do I see which RHEL and RHCOS version is in a release? How do I see from which openshift/os commit it's built?

Like above, but add `oc image info`:

```bash
$ oc image info $(oc adm release info --image-for=rhel-coreos quay.io/openshift-release-dev/ocp-release:4.16.11-x86_64)
...
Labels:     ...
            io.openshift.build.versions=machine-os=416.94.202409040013-0
            org.opencontainers.image.revision=2f419467be49446862f180b2fc0e5d94f5639a6a
            org.opencontainers.image.source=https://github.com/openshift/os
            org.opencontainers.image.version=416.94.202409040013-0
```

Here the `94` means it's using RHEL 9.4.
The `revision` commit hash points to the git commit of openshift/os that was built.

## Q: How do I know which RHEL will be in the next release? What are the current versions of RHEL being used in RHCOS?

RHEL CoreOS consumes content from RHEL y-stream releases that have an Extended Update Support (EUS) period of their lifecycle.  See the [RHEL Lifecycle page](https://access.redhat.com/support/policy/updates/errata) for more information.

We generally don't make any statements about which version of RHEL will be used in future OCP/RHCOS releases.

The table below describes the versions of RHCOS/OCP and which versions of RHEL being used.

RHCOS/OCP version | RHEL version
---|---
4.6 | 8.2 EUS
4.7 | 8.4 EUS
4.8 | 8.4 EUS
4.9 | 8.4 EUS
4.10 | 8.4 EUS
4.11 | 8.6 EUS
4.12 | 8.6 EUS
4.13 | 9.2 EUS
4.14 | 9.2 EUS
4.15 | 9.2 EUS
4.16 | 9.4 EUS
4.17 | 9.4 EUS
4.18 | 9.4 EUS
4.19 | 9.6 EUS
4.20 | 9.6 EUS
4.21 | 9.6 EUS

## Q: How do I determine what version of an RPM is included in an RHCOS release?

One normally does not care about a specific RHCOS release, but rather a specific
_OpenShift release_. In that case, head over to [the release controller's
page](https://amd64.ocp.releases.ci.openshift.org/) for that release. (Other
arches: [arm64](https://arm64.ocp.releases.ci.openshift.org/),
[s390x](https://s390x.ocp.releases.ci.openshift.org/),
[ppc64le](https://ppc64le.ocp.releases.ci.openshift.org/).)

For 4.19 and newer, the package list is rendered by the release controller
itself in the Node Image Info section. For 4.18 and older, the release
controller will link to the internal RHCOS build browser (VPN required).

### Finding RPM information from the CLI

It is also possible to get this information from the CLI but it requires a pull
secret. Starting from 4.19+, it's possible to query the RPM list using `oc`:

```
$ # note this requires a pull secret set up at the canonical locations or in $REGISTRY_AUTH_FILE
$ oc adm release info --rpmdb --rpmdb-cache=/tmp/rpmdbs \
    quay.io/openshift-release-dev/ocp-release:4.20.0-ec.0-x86_64
Package contents:
  NetworkManager-1:1.52.0-1.el9_6
  ...
```

This is a cheap operation and _does not_ download the whole image.

For older releases, you can use the OpenShift release controller to get a link to the internal RHEL CoreOS release browser. Alternatively, since 4.12, the operating system is shipped as a bootable container image, which means you can do:

```bash
$ podman run --rm -ti $(oc adm release info --image-for=rhel-coreos quay.io/openshift-release-dev/ocp-release:4.18.14-x86_64) rpm -q kernel
kernel-5.14.0-427.68.1.el9_4.x86_64
$
```

But note this downloads the whole image. Also note that for OpenShift 4.12, the image name was `rhel-coreos-8` and not `rhel-coreos`.

For releases older than 4.12 which used `machine-os-content`, key packages such as the kernel are exposed as metadata properties:

```bash
$ oc image info (oc adm release info --image-for=machine-os-content quay.io/openshift-release-dev/ocp-release:4.9.0-rc.1-x86_64) | grep com.coreos.rpm
             com.coreos.rpm.cri-o=1.22.0-68.rhaos4.9.git011c10a.el8.x86_64
             com.coreos.rpm.ignition=2.12.0-1.rhaos4.9.el8.x86_64
             com.coreos.rpm.kernel=4.18.0-305.17.1.el8_4.x86_64
             com.coreos.rpm.kernel-rt-core=4.18.0-305.17.1.rt7.89.el8_4.x86_64
             com.coreos.rpm.ostree=2020.7-5.el8_4.x86_64
             com.coreos.rpm.rpm-ostree=2020.7-3.el8.x86_64
             com.coreos.rpm.runc=1.0.0-74.rc95.module+el8.4.0+11822+6cc1e7d7.x86_64
             com.coreos.rpm.systemd=239-45.el8_4.3.x86_64
$
```

## Q: How do I manually find the extension RPMs?

As above, first check the release controller's page for the OpenShift release
you're interested in. 

For 4.19 and later, this information is rendered by the release controller
itself in the Node Image Info section. For older releases, the release
controller will link to the RHCOS release browser (VPN required) where extension
metadata is available.

### Finding extensions RPM information from the CLI

In 4.19 and later, it's possible to cheaply query the extensions list:

```bash
$ oc image extract "$(oc adm release info --image-for=rhel-coreos-extensions quay.io/openshift-release-dev/ocp-release:4.19.0-rc.3-x86_64)[-1]" --file usr/share/rpm-ostree/extensions.json
$ jq . extensions.json
{
  "NetworkManager-libreswan": "1.2.24-1.el9.x86_64",
  "bison": "3.7.4-5.el9.x86_64",
  "capstone": "4.0.2-10.el9.x86_64",
  "corosync": "3.1.9-2.el9_6.x86_64",
  ...
```

In 4.13 and later, extensions are shipped as a separate image. The image name is
`rhel-coreos-extensions` and the RPMs are located in `/usr/share/rpm-ostree/extensions`.
The container also works as an HTTP server serving repodata containing the extensions
RPMs (port 9091).

In 4.12 and earlier, the extension RPMs are shipped as part of the
`machine-os-content` image (in the `/extensions` directory of the image). As above, you
can use `oc adm release info` to get the `machine-os-content` image URL for a
particular release, and then e.g. use `oc image extract` or `podman create` +
`podman copy` to extract the RPMs.

## Q: How do I debug Ignition failures?

Today, when Ignition fails, it will wait in an "emergency shell" for 5 minutes.
The intention is to avoid "partially provisioned" systems.  To debug things,
here are a few tips and tricks.

In the emergency shell, you can use `systemctl --failed` to show units which failed.
From there, `journalctl -b -u <unit>` may help - for example, `journalctl -b -u ignition-files.service`.

Usually, you'll have networking in the initramfs, so you can also use e.g. `curl` to extract data.
See for example [this StackExchange question](https://unix.stackexchange.com/a/108495).

See also <https://github.com/coreos/ignition/issues/585>

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

As of OpenShift 4.3, RHCOS has a unified BIOS/UEFI partition layout. As such, it is not compatible with the default `aws ec2 import-image` API (for more information, see discussions in <https://github.com/openshift/os/pull/396>).

Instead, you must use `aws ec2 import-snapshot` combined with `aws ec2 register-image`. To learn more about these APIs, see the AWS documentation for [importing snapshots](https://docs.aws.amazon.com/vm-import/latest/userguide/vmimport-import-snapshot.html) and [creating EBS-backed AMIs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/creating-an-ami-ebs.html#creating-launching-ami-from-snapshot).

In the future the OpenShift installer will likely have support for this.

## Q: Can I use Driver Update Program disks with RHCOS?

No, there is no supported mechanism for non-default kernel modules at this time, which includes [driver disks](https://access.redhat.com/articles/64322).

## Q: How do I capture console logs from an RHCOS node running on vSphere?

It's possible to write the serial console data directly to the VMFS volume.  You can do this by changing the Virtual Hardware settings of the VM to include a serial port that writes to a file (see [screenshot](https://raw.githubusercontent.com/openshift/os/master/docs/vsphere-settings.png)).  The [official documetation](https://docs.vmware.com/en/VMware-vSphere/7.0/com.vmware.vsphere.vm_admin.doc/GUID-C6FBCF66-5796-4EE6-BF47-4DCAA9DCD1E3.html) from VMware has additional details.

Alternatively, you can try the [OpenStack VMWare Virtual Serial Port Concentrator container](https://github.com/jcpowermac/vmware-vspc-container).

## Q: How do I log into a node via console?

See <https://access.redhat.com/solutions/5500131>
The FCOS equivalent is <https://docs.fedoraproject.org/en-US/fedora-coreos/access-recovery/>

## Q: Does RHCOS support multipath on the primary disk?

Yes. Multipath is turned on at installation time by using:

```bash
coreos-installer install --append-karg rd.multipath=default --append-karg root=/dev/disk/by-label/dm-mpath-root --append-karg rw ...
```

(The `rw` karg is required whenever `root` is specified so that systemd mounts it read-write. This matches what `rdcore rootmap` normally does in non-multipath situations.)

If your environment permits it, it's also possible to turn on multipath as a day-2 operation using a MachineConfig object which appends the same kernel arguments. Note however that in some setups, any I/O to non-optimized paths will result in I/O errors. And since there is no guarantee which path the host may select prior to turning on multipath, this may break the system. In these cases, you must enable multipathing at installation time.

## Q: How do I manually mount the `coreos-luks-root-nocrypt` root partition?

Old versions of RHCOS have a "dummy cryptsetup" when LUKS is not enabled.  It is set up via `dm-linear` which creates a block device that skips the unused LUKS header.

You can see [this code](https://github.com/openshift/os/blob/f73c9a15334ca41afb7a7d68fc9d838ab1c3e369/overlay.d/05rhcos/usr/libexec/coreos-cryptfs#L141-L143) for how it's mounted, and run those commands to do so outside of a booted host.

## Q: Does RHCOS support multipath on secondary disks?

Yes, however setting this up is currently awkward to do. You must set everything up through Ignition units. The following kola test which creates a filesystem on a multipathed device and mounts it at `/var/lib/containers` shows how to do this:
https://github.com/coreos/coreos-assembler/blob/e98358a42c80a78789295d2b44abe96e885246fb/mantle/kola/tests/misc/multipath.go#L36-L94

Do *not* add `rd.multipath` or `root` unless the primary disk is also multipathed.

### Q: How can multipath settings be modified?

Currently, non-default multipath configurations for the primary disk cannot be set at `coreos-installer` time. You may configure multipath using Ignition or MachineConfigs to modify `/etc/multipath.conf` or ideally to add `/etc/multipath/conf.d` dropins. Configuration documentation for traditional RHEL applies (see docs [here](https://access.redhat.com/documentation/en-us/red_hat_enterprise_linux/8/html/configuring_device_mapper_multipath/index)). If you need these customized settings to take effect from the initrd, then you can add it as an initramfs overlay via `rpm-ostree initramfs-etc --track /etc/multipath.conf --track /etc/multipath` and removing the `rd.multipath=default` kernel argument (e.g. `rpm-ostree kargs --delete rd.multipath=default`).

## Q: Does RHCOS support booting off of iSCSI?

### via HBA

If the device is connected to the host via a HBA then it'll show up transparently as a local disk and should work fine.

### via iBFT

At coreos-installer time, you need to add the `rd.iscsi.firmware=1` karg. E.g.

```
coreos-installer install --append-karg rd.iscsi.firmware=1
```

### via custom initiation

At coreos-installer time, you need to add the `rd.iscsi.initiator` and `netroot` kargs. E.g.:

```
coreos-installer --append-karg rd.iscsi.initiator=iqn.2023-11.coreos.diskless:testsetup \
  --append-karg netroot=iscsi:10.0.2.15::::iqn.2023-10.coreos.target.vm:coreos
```

See [the dracut documentation](https://www.man7.org/linux/man-pages/man7/dracut.cmdline.7.html) for more information.

### With Multipathing

In addition to the kargs above, you can add `rd.multipath=default` as well if
the target device is multipathed. (And e.g. if using iPXE, you likely would
then also want to specify all the paths to the `sanboot` command in your iPXE
script, see e.g. [this test config](https://github.com/coreos/coreos-assembler/blob/8a354045c68e5dce8cd5736dc6fdcfac1d603b35/mantle/cmd/kola/resources/iscsi_butane_setup.yaml#L70-L71).)

Similarly to the above, in the custom initiation case you need to add the
`rd.iscsi.initiator` and `netroot` kargs. Specify as many `netroot` kargs as
there are paths, e.g.:

```
coreos-installer --append-karg rd.iscsi.initiator=iqn.2023-11.coreos.diskless:testsetup \
  --append-karg netroot=iscsi:10.0.2.15::::iqn.2023-10.coreos.target.vm:coreos \
  --append-karg netroot=iscsi:10.0.2.16::::iqn.2023-10.coreos.target.vm:coreos \
  --append-karg rd.multipath=default
```

## Q: How do I configure a secondary block device via Ignition/MC if the name varies on each node?

First, verify that there isn't a `/dev/disk/by-*` symlink which works for your needs. If not, a few approaches exist:
- If this is a fresh install and you're using the live environment to install RHCOS, as part of the install flow you can inspect the machine (by hand, or scripted) to imperatively figure out what the block device should be according to your own heuristics (e.g. "the only multipath device there is", or "the only NVMe block device"). You can then e.g. "render" the final Ignition config with the device path to pass to `coreos-installer` or directly partition it and optionally format it and use a consistent partition (and optionally filesystem) label that will be available to use in the generic Ignition config.
- In the most generic case, you will have to set up the block device completely outside of Ignition. This means having your Ignition config write out a script (and a systemd unit that executes it) that does the probing in the real root to select the right block device and format it. You should still be able to write out the mount unit via Ignition. Here's an example Butane config that leverages environment files in the mount unit to dynamically select the device:

```yaml
variant: fcos
version: 1.4.0
systemd:
  units:
    - name: find-secondary-device.service
      enabled: true
      contents: |
        [Unit]
        DefaultDependencies=false
        After=systemd-udev-settle.service
        Before=local-fs-pre.target
        ConditionPathExists=!/etc/found-secondary-device

        # break boot if we fail
        OnFailure=emergency.target
        OnFailureJobMode=isolate

        [Service]
        Type=oneshot
        RemainAfterExit=yes
        ExecStart=/etc/find-secondary-device

        [Install]
        WantedBy=multi-user.target
    - name: var-lib-foobar.mount
      enabled: true
      contents: |
        [Unit]
        Before=local-fs.target

        [Mount]
        What=/dev/disk/by-label/foobar
        Where=/var/lib/foobar
        Type=xfs

        [Install]
        RequiredBy=local-fs.target
storage:
  files:
    # put in /etc since /var isn't mounted yet when we need to run this
    - path: /etc/find-secondary-device
      mode: 0755
      contents:
        inline: |
          #!/bin/bash
          set -xeuo pipefail

          # example heuristic logic for finding the block device
          for serial in foobar bazboo; do
            blkdev=/dev/disk/by-id/virtio-$serial
            if [ -b "$blkdev" ]; then
              mkfs.xfs -f "$blkdev" -L foobar
              echo "Found secondary block device $blkdev" >&2
              touch /etc/found-secondary-device
              exit
            fi
          done

          echo "Couldn't find secondary block device!" >&2
          exit 1
```

Note this approach uses `After=systemd-udev-settle.service` which is not usually desirable as it may slow down boot. Another related approach is writing a udev rule to create a more stable symlink instead of this dynamic systemd service + script approach.

This script is also written in a way that also makes it compatible to be used day-2 via a MachineConfig.

The larger issue tracking machine-specific MachineConfigs is at https://github.com/openshift/machine-config-operator/issues/1720.

## Q: Does RHCOS support the use of `NetworkManager` keyfiles?  Does RHCOS support the use of `ifcfg` files?

Starting with RHCOS 4.6, it is possible to use either `NetworkManager` keyfiles or `ifcfg` files for configuring host networking.  It is strongly preferred to use `NetworkManager` keyfiles.

## Q: How do I request the inclusion of a new package in RHCOS?

RHCOS inherits the majority of its configuration from Fedora CoreOS, so we aim to keep the package manifests between the two as closely aligned as possible. If you wish to have a package added to RHCOS, you should first suggest the inclusion of the package in Fedora CoreOS via a [new issue on the fedora-coreos-tracker repo](https://github.com/coreos/fedora-coreos-tracker/issues/new?assignees=&labels=kind%2Fenhancement&template=new-package.md&title=New+Package+Request%3A+%3Cpackage+name%3E).

If the package makes sense to include in Fedora CoreOS, it will ultimately be included in RHCOS in the future when the [fedora-coreos-config](https://github.com/coreos/fedora-coreos-config) submodule is updated in this repo.

If the package is **not** included in Fedora CoreOS, you may submit a PR to this repo asking for the inclusion of the package with the reasoning for including it.

## Q: How do I replace the current Kernel with Kernel-RT or a new Kernel version in RHCOS?

Understanding the model:
- kernel is a base package, so removing or replacing it is done with `rpm-ostree override replace/remove`.
- kernel-rt is a layered package, so installing or uninstalling it is done with
  `rpm-ostree install/uninstall`.
- rpm-ostree only allows a single kernel to be installed so if installing
  `kernel-rt`, you have to remove `kernel`. Similarly, if uninstalling
  `kernel-rt`, you have to restore (reset) `kernel`.

The examples below use kernel-rt, but it's a similar process for the kernel-64k package on aarch64.

#### kernel -> kernel-rt

```
rpm-ostree override remove kernel kernel-core kernel-modules kernel-modules-extra \
  --install kernel-rt-core-4.18.0-305.34.2.rt7.107.el8_4.x86_64.rpm \
  --install kernel-rt-kvm-4.18.0-305.34.2.rt7.107.el8_4.x86_64.rpm \
  --install kernel-rt-modules-4.18.0-305.34.2.rt7.107.el8_4.x86_64.rpm \
  --install kernel-rt-modules-extra-4.18.0-305.34.2.rt7.107.el8_4.x86_64.rpm
```

#### kernel-rt -> kernel

If you have nothing else layered (e.g. `usbguard`), you can use a simpler command

```
rpm-ostree reset --overlays --overrides
```

Otherwise, to exactly undo just the kernel -> kernel-rt transition:

```
rpm-ostree override reset kernel kernel-core kernel-modules kernel-modules-extra \
  --uninstall kernel-rt-core \
  --uninstall kernel-rt-kvm \
  --uninstall kernel-rt-modules \
  --uninstall kernel-rt-modules-extra
```

#### Replacing kernel with a different version

```
rpm-ostree override replace \
  kernel-{,modules-,modules-extra-,core-}4.18.0-305.34.2.107.el8_4.x86_64.rpm
```

#### Replacing kernel-rt with a different version

```
rpm-ostree uninstall kernel-rt-core kernel-rt-kvm kernel-rt-modules kernel-rt-modules \
  --install kernel-rt-core-4.18.0-305.34.2.rt7.107.el8_4.x86_64.rpm \
  --install kernel-rt-kvm-4.18.0-305.34.2.rt7.107.el8_4.x86_64.rpm \
  --install kernel-rt-modules-4.18.0-305.34.2.rt7.107.el8_4.x86_64.rpm \
  --install kernel-rt-modules-extra-4.18.0-305.34.2.rt7.107.el8_4.x86_64.rpm
```

## Q: How do I install RHCOS on top of a RAID device?

### Hardware RAID

This is transparent to RHCOS and shows up as a unified block device. You should be able to target `coreos-installer install` at that device as usual.

### Software RAID

RHCOS supports software RAID1 via high-level sugar: https://docs.openshift.com/container-platform/4.15/installing/install_config/installing-customizing.html#installation-special-config-mirrored-disk_installing-customizing

### Fake RAID/Hybrid RAID/Intel VROC

Some systems support what is known as Fake or Hybrid RAID, where some of the work of maintaining the RAID is offloaded to the hardware, but otherwise it appears just like software RAID to the OS.

To install to these devices, configure them as necessary in the firmware and/or using `mdadm` as documented.

#### Intel VROC

To configure an Intel VROC-enabled RAID1, first create the IMSM container, e.g.:

```
mdadm -CR /dev/md/imsm0 -e imsm -n2 /dev/nvme0n1 /dev/nvme1n1
```

Then, create the RAID1 inside of that container. Due to a gap in RHCOS, we create a dummy RAID0 volume in front of the real RAID1 one that we then delete:

```
# create dummy array
mdadm -CR /dev/md/dummy -l0 -n2 /dev/md/imsm0 -z10M --assume-clean
# create real RAID1 array
mdadm -CR /dev/md/coreos -l1 -n2 /dev/md/imsm0

# stop member arrays and delete dummy one
mdadm -S /dev/md/dummy
mdadm -S /dev/md/coreos
mdadm --kill-subarray=0 /dev/md/imsm0

# restart arrays
mdadm -A /dev/md/coreos /dev/md/imsm0
```

Then when installing RHCOS, point `coreos-installer install` at the RAID1 device and include the `rd.md.uuid` karg pointing at the UUID *of the IMSM container*. E.g.:

```
eval $(mdadm --detail --export /dev/md/imsm0)
coreos-installer install /dev/md/coreos --append-karg rd.md.uuid=$MD_UUID \
  <other install args as usual, e.g. --ignition-url, --console, ...>
```
