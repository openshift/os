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
- Clone the config repo (`openshift/os`):
  ```
  # Main developement branch, default version
  $ cosa init https://github.com/openshift/os.git

  # Release specific branch, default version
  $ cosa init --branch release-4.10 https://github.com/openshift/os.git
  ```
- **Optional and temporary workaround until we have variant support in COSA:**
  Manually select the RHCOS variant. This is not needed if you want to buid the
  default variant:
  ```
  $ ln -snf "manifest-rhel-9.0.yaml" "src/config/manifest.yaml"
  $ ln -snf "extensions-rhel-9.0.yaml" "src/config/extensions.yaml"
  $ ln -snf "image-rhel-9.0.yaml" "src/config/image.yaml"
  ```
- Clone the internal `redhat-coreos` repo:
  ```
  # Main developement branch
  $ git clone https://.../redhat-coreos.git

  # Release specific branch
  $ git clone --branch 4.11 https://.../redhat-coreos.git
  ```
- Copy the repo files and the `content_sets.yaml` file from the `redhat-coreos`
  repo into `src/config` (`openshift/os`):
  ```
  # For 4.9, 4.10 and 4.11, copy all repo files and content_sets:
  $ cp redhat-coreos/*.repo src/config/
  $ cp redhat-coreos/content_sets.yaml src/config/

  # For 4.12 and later, when building the default variant, copy the default
  # repo and content_sets files:
  $ cp redhat-coreos/rhel-8.6.repo src/config/
  $ cp redhat-coreos/content_sets-rhel-8.6.yaml src/config/content_sets.yaml

  # For 4.12 and later, if you want to build a non-default variant then you
  # have to copy the corresponding versioned files:
  $ cp redhat-coreos/rhel-9.0.repo src/config/
  $ cp redhat-coreos/content_sets-rhel-9.0.yaml src/config/content_sets.yaml
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
