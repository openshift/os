# Building and developing Red Hat Enterprise Linux CoreOS

## Background

RHEL CoreOS (RHCOS) is a derivative of Red Hat Enterprise Linux (RHEL), CentOS
Strema CoreOS (SCOS) and Fedora CoreOS (FCOS). The tool to build RHCOS, SCOS
and FCOS is [coreos-assembler]. The process detailled here is thus very similar
to the one described in [Building Fedora CoreOS] or [Building and developing
CentOS Stream CoreOS](development-scos.md) but requires access to Red Hat
internal resources.

## Build process

Note that this documentation applies only to RHCOS versions starting with 4.9
and later. For older versions, see the internal documentation.

- Make sure you're meeting the [prerequisites].

- Make sure that you have setup the Red Hat internal CA on your system and that
  you are connected to the Red Hat VPN.

- Setup a `cosa` alias, following the [upstream documentation][cosa-alias].
  - Note: If you encounter DNS resolution issues with COSA when on the Red Hat
    VPN, you should try adding `--net=host` to the podman invocation.

- Always make sure that you are using the *latest build* of the specific
  version of the COSA container matching with the version of RHCOS that you
  want to build:
  ```
  # Use the latest version for the main developement branch:
  # The export command below is optional here as it is the default
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
  directory for each version is recommended:
  ```
  $ mkdir rhcos-4.11
  $ cd rhcos-4.11
  ```

- Get the following values from the internal documentation:
  ```
  export RH_CA="..."
  export RHCOS_REPO="..."
  ```

- Clone the config repo (`openshift/os`), passing as argument the internal Git 
  repo which includes the RPM repo configs and optionaly the specific branch. 
  As the Red Hat CA are not included in the cosa container by default, we spawn 
  a shell inside the COSA container and add them manually for the initial clone:
  ```
  $ cosa shell
  [coreos-assembler]$ export RH_CA="..."
  [coreos-assembler]$ export RHCOS_REPO="..."
  [coreos-assembler]$ sudo curl -kL -o /etc/pki/ca-trust/source/anchors/Red_Hat_IT_Root_CA.crt "${RH_CA}"
  [coreos-assembler]$ sudo update-ca-trust

  # Main developement branch, default version
  [coreos-assembler]$ cosa init \
        --yumrepo "${RHCOS_REPO}" \
        https://github.com/openshift/os.git

  # Main developement branch, selecting a specific variant
  [coreos-assembler]$ cosa init \
        --yumrepo "${RHCOS_REPO}" \
        --variant rhel-coreos-9 \
        https://github.com/openshift/os.git

  # Specific release branch, selecting a specific variant
  [coreos-assembler]$ cosa init \
        --branch release-4.12 \
        --variant rhel-coreos-9 \
        --yumrepo "${RHCOS_REPO}" \
        https://github.com/openshift/os.git
  ```
  You can then close the temporary `cosa shell` environment:
  ```
  [coreos-assembler]$ exit
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

## Overriding packages for testing

- If you need to override a file or a package for local testing, you can place
  those into the `override/rootfs` or `override/rpm` directory before building
  the image. See the [Using overrides] section from the [COSA
  documentation][coreos-assembler].

[coreos-assembler]: https://github.com/coreos/coreos-assembler/
[Building Fedora CoreOS]: https://coreos.github.io/coreos-assembler/building-fcos/
[prerequisites]: https://coreos.github.io/coreos-assembler/building-fcos/#getting-started---prerequisites
[cosa-alias]: https://coreos.github.io/coreos-assembler/building-fcos/#define-a-bash-alias-to-run-cosa
[buildextend]: https://coreos.github.io/coreos-assembler/cosa/#buildextend-commands
[kola]: https://coreos.github.io/coreos-assembler/kola/
[Using overrides]: https://coreos.github.io/coreos-assembler/working/#using-overrides
