# Building and developing CentOS Stream CoreOS

## Background

CentOS Stream CoreOS (SCOS) is a derivative of both CentOS Stream and Fedora
CoreOS (FCOS). The tool to build both SCOS and FCOS is [coreos-assembler]. The
process detailled here is thus very similar to the one described in [Building
Fedora CoreOS].

## Build process

- Make sure you're meeting the [prerequisites].
- Setup a `cosa` alias, following the [upstream documentation][cosa-alias].
- Always make sure that you have the latest version of the COSA container:
  ```
  $ podman pull quay.io/coreos-assembler/coreos-assembler
  ```
- Create and use a dedicated directory:
  ```
  $ mkdir scos
  $ cd scos
  ```
- Clone the config repo (`openshift/os`):
  ```
  $ cosa init https://github.com/openshift/os.git
  ```
- **Temporary workaround until we have variant support in COSA:** Manually
  select the SCOS variant:
  ```
  $ ln -snf "manifest-c9s.yaml" "src/config/manifest.yaml"
  $ ln -snf "extensions-c9s.yaml" "src/config/extensions.yaml"
  $ ln -snf "image-c9s.yaml" "src/config/image.yaml"
  ```
- Setup the CentOS Stream 9 repos:
  ```
  $ cp "src/config/repos/c9s.repo" "src/config/c9s.repo"
  ```
- **Temporary workaround until we have full repos for SCOS:** Add the internal
  `rhel-9-server-ose` repo definition from RHCOS to `c9s.repo`:
  ```
  [rhel-9-server-ose]
  enabled=1
  gpgcheck=0
  baseurl=http://...
  ```
- Fetch packages and build SCOS ostree container and QEMU image:
  ```
  $ cosa fetch
  $ cosa build
  ```

## Building SCOS images for other platforms than QEMU

- You can build images for platforms that are supported in COSA using the
  [`buildextend` commands][buildextend]:
  ```
  $ cosa buildextend-aws
  $ cosa buildextend-openstack
  ```

## Running SCOS locally for testing

- You may then run an ephemeral virtual machine using QEMU with:
  ```
  $ cosa run
  ```

## Testing SCOS with kola

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
