# Building and developing Red Hat Enterprise Linux CoreOS

## Background

RHEL CoreOS (RHCOS) is a derivative of both RHEL and Fedora CoreOS (FCOS). The
tool to build both RHCOS and FCOS is [coreos-assembler]. The process detailled
here is thus very similar to the one described in [Building Fedora CoreOS].

## Build process

This build process is very similar to the one used for [CentOS Stream
CoreOS](development-scos.md) but requires access to Red Hat internal resources.

Note that this applies only to RHCOS versions starting with 4.9 and later. For
older versions, see the internal documentation.

- Make sure you're meeting the [prerequisites].
- Setup a `cosa` alias, following the [upstream documentation][cosa-alias].
- Always make sure that you are using the *latest build* of the specific
  version of the COSA container matching with the version of RHCOS that you
  want to build:
  ```
  # Use the latest version for the main developement branch:
  # The export command is optional here as it is the default
  $ export COREOS_ASSEMBLER_CONTAINER=quay.io/coreos-assembler/coreos-assembler:latest
  $ podman pull quay.io/coreos-assembler/coreos-assembler

  # For branched releases:
  $ export COREOS_ASSEMBLER_CONTAINER=quay.io/coreos-assembler/coreos-assembler:rhcos-4.10
  $ podman pull quay.io/coreos-assembler/coreos-assembler:rhcos-4.10
  ```
- Create and use a dedicated directory:
  ```
  $ mkdir rhcos
  $ cd rhcos
  ```
  If you're going to work on multiple versions of RHCOS, using a dedicated
  directory for each version is recommended (i.e.  `rhcos-4.11`).

- **For 4.12 and later only:** Clone the config repo (`openshift/os`), passing
  as argument the internal Git repo which includes the RPM repo configs and
  optionaly the specific branch:
  ```
  # Main developement branch, default version
  $ cosa init \
        --yumrepo https://.../redhat-coreos.git \
        https://github.com/openshift/os.git

  # Main developement branch, selecting a specific variant
  $ cosa init \
        --yumrepo https://.../redhat-coreos.git \
        --variant rhel-coreos-9 \
        https://github.com/openshift/os.git

  # Specific release branch, selecting a specific variant
  $ cosa init \
        --branch release-4.12 \
        --variant rhel-coreos-9 \
        --yumrepo https://.../redhat-coreos.git \
        https://github.com/openshift/os.git
  ```

- **For 4.11 and earlier only:**
  - Clone the config repo (`openshift/os`) on the specific branch:
    ```
    $ cosa init --branch release-4.10 https://github.com/openshift/os.git
    ```
  - Clone the internal `redhat-coreos` repo with the correct branch:
    ```
    $ git clone --branch 4.11 https://.../redhat-coreos.git
    ```
  - Copy the repo files and the `content_sets.yaml` file from the
    `redhat-coreos` repo into `src/config` (`openshift/os`):
    ```
    $ cp redhat-coreos/*.repo src/config/
    $ cp redhat-coreos/content_sets.yaml src/config/
    ```

- Fetch packages and build RHCOS ostree container and QEMU image:
  ```
  $ cosa fetch
  $ cosa build
  ```

## Building RHCOS images for other platforms than QEMU

- You can build images for platforms that are supported in COSA using the
  [`buildextend` commands][buildextend]:
  ```
  $ cosa buildextend-aws
  $ cosa buildextend-openstack
  ```

## Running RHCOS locally for testing

- You may then run an ephemeral virtual machine using QEMU with:
  ```
  $ cosa run
  ```

## Testing RHCOS with kola

- You may then run tests on the image built with [`kola`][kola]:
  ```
  # Run basic QEMU scenarios
  $ cosa kola --basic-qemu-scenarios
  # Run all kola tests (internal & external)
  $ cosa kola run --parallel 2
  ```

[coreos-assembler]: https://github.com/coreos/coreos-assembler/
[Building Fedora CoreOS]: https://coreos.github.io/coreos-assembler/building-fcos/
[prerequisites]: https://coreos.github.io/coreos-assembler/building-fcos/#getting-started---prerequisites
[cosa-alias]: https://coreos.github.io/coreos-assembler/building-fcos/#define-a-bash-alias-to-run-cosa
[buildextend]: https://coreos.github.io/coreos-assembler/cosa/#buildextend-commands
[kola]: https://coreos.github.io/coreos-assembler/kola/
