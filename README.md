# OpenShift Node Image

This repository defines the OpenShift node image. This is the `rhel-coreos` or
`stream-coreos` image in the OpenShift release payload.

The extensions image (i.e. `rhel-coreos-extensions`) is also defined here, in
[the extensions directory](extensions/).

> [!NOTE]
> Historically, this repo also contained the manifests for RHEL CoreOS (RHCOS)
> and CentOS Stream CoreOS (SCOS). These manifests now live [in a separate
> repo](https://github.com/coreos/rhel-coreos-config). That repo produces a
> _base image_ containing only RHEL/CentOS Stream content. _This_ repo builds
> `FROM` that base image and adds OpenShift components (`kubelet`, `oc`,
> `cri-o`, etc.).

## Building

See the instructions in [building.md](docs/building.md).

## Reporting issues

The issue tracker for this repository is only used to track the development work
related to the OpenShift node image.

**Please report OKD or CentOS Stream CoreOS issues in the [OKD issue tracker].**

**Please see this [FAQ entry for Red Hat support](docs/faq.md#q-where-should-i-report-issues-with-openshift-container-platform-or-red-hat-coreos).**

## Frequently Asked Questions

A lot of common questions are answered in the [FAQ](docs/faq.md).

[coreos-assembler]: https://github.com/coreos/coreos-assembler/
[OKD issue tracker]: https://github.com/openshift/okd/issues
[variants]: https://github.com/coreos/coreos-assembler/blob/065cd2d20e379642cc3a69e498d20708e2243b21/src/cmd-init#L45-L48
