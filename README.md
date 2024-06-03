# RHEL CoreOS and CentOS Stream CoreOS config

This repository is the "config" repository used to build RHEL CoreOS and CentOS
Stream CoreOS using [coreos-assembler].

There was a previous git repository inside the Red Hat firewall that was never
published. The history of that repository is entangled with various private
things and is omitted. This repository is now canonical.

## Variants

To support building both a RHEL-based and a CentOS Stream-based CoreOS, the
coreos-assembler concept of [variants] is used. The following variants are
supported:

- `rhel-9.4`: RHEL 9.4-based CoreOS; without OpenShift components.
- `ocp-rhel-9.4`: RHEL 9.4-based CoreOS; including OpenShift components.
- `c9s`/`c10s`: CentOS Stream-based CoreOS, without OKD components.
- `okd-c9s`/`okd-c10s`: CentOS Stream-based CoreOS, including OpenShift components. This
  currently includes some packages from RHEL because not all packages required
  by OpenShift are provided in CentOS Stream.

In the future, the `ocp-*` variants will be removed. Instead, OpenShift
components will be layered by deriving from the `rhel-9.4`/`c9s` images.

The default variant is `ocp-rhel-9.4`.

## Reporting issues

The issue tracker for this repository is only used to track the development
work related to RHEL CoreOS.

**Please report OKD or CentOS Stream CoreOS issues in the [OKD issue tracker].**

**Please see this [FAQ entry for Red Hat support](docs/faq.md#q-where-should-i-report-issues-with-openshift-container-platform-or-red-hat-coreos).**

## Frequently Asked Questions

A lot of common questions are answered in the [FAQ](docs/faq.md).

## Building and developing CentOS Stream CoreOS

See the [SCOS development doc](docs/development-scos.md).

## Building and developing RHEL CoreOS

See the [RHCOS development doc](docs/development-rhcos.md).

## CI Configuration

See [OpenShift CI notes](docs/openshift-ci-notes.md) for more information.

[coreos-assembler]: https://github.com/coreos/coreos-assembler/
[OKD issue tracker]: https://github.com/openshift/okd/issues
[variants]: https://github.com/coreos/coreos-assembler/blob/065cd2d20e379642cc3a69e498d20708e2243b21/src/cmd-init#L45-L48
