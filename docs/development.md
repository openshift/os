# Building and developing Red Hat Enterprise Linux CoreOS

## Background

RHEL CoreOS (RHCOS) is a derivative of both RHEL and Fedora CoreOS (FCOS). The
tool to build both RHCOS and FCOS is [coreos-assembler]. The process detailled
here is thus very similar to the one described in [Building Fedora CoreOS].

## Build process

This build process is very similar to the one used for [CentOS Stream
CoreOS][SCOS] but requires access to Red Hat internal resources.

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

[SCOS]: development-scos.md

[coreos-assembler]: https://github.com/coreos/coreos-assembler/
[Building Fedora CoreOS]: https://coreos.github.io/coreos-assembler/building-fcos/
[prerequisites]: https://coreos.github.io/coreos-assembler/building-fcos/#getting-started---prerequisites
[cosa-alias]: https://coreos.github.io/coreos-assembler/building-fcos/#define-a-bash-alias-to-run-cosa
[buildextend]: https://coreos.github.io/coreos-assembler/cosa/#buildextend-commands
[kola]: https://coreos.github.io/coreos-assembler/kola/

---

## Notes about repositories

The RHEL repositories are only available to Red Hat customers, and it's likely
that you want to use a mirror. And further, a common scenario is to inject
specific versioned rpm-md repositories to test different snapshots or
"composes".  For these reasons, you need to provide the repos of input RPMs.

To do so, create a `rhcos.repo` file that looks like this:

```text
# RHEL repos
[rhel-8-baseos]
baseurl=<url>

[rhel-8-appstream]
baseurl=<url>

[rhel-8-fast-datapath]
baseurl=<url>

# These are the OpenShift RPMs, see https://mirror.openshift.com/pub/openshift-v4/dependencies/rpms/
# except there's things like afterburn that are only internal right now unfortunately.
[rhel-8-server-ose]
baseurl=<url>
```

The names of the repos must match those in `manifest.yaml`.

See also <https://github.com/openshift/release/blob/master/core-services/release-controller/README.md#rpm-mirrors>.

## Updating FCOS

As noted above, RHCOS uses FCOS as an upstream. This is implemented by
inheriting from the [fedora-coreos-config](https://github.com/coreos/fedora-coreos-config/)
repository as a git submodule; the RHCOS manifests and overlays include parts
(though not all) of FCOS.

After a change is landed in FCOS, it's often OK to also immediately update
RHCOS' main branch to the latest FCOS. We try to keep things compatible.

```bash
$ (cd fedora-coreos-config && git fetch origin && git reset --hard origin/testing-devel)
$ git commit -a -m 'Update FCOS'
```

Note that this is now mostly automated with a bot.

## Debugging failures in app.ci

Occasionally it is necessary to debug test failures on the [OpenShift CI clusters](https://docs.ci.openshift.org/docs/getting-started/useful-links/#clusters)
by scheduling a `cosa` pod on the cluster. There's a few additional steps after
getting the pod scheduled, in order to be able to build and test RHCOS.

1. Create the pod

Using the YAML below, create a new pod with `oc create -f pod.yaml`

```yaml
apiVersion: v1
kind: Pod
metadata:
  # Replace this with e.g. $USER-cosa
  name: test-cosa
spec:
  containers:
  - args:
    - shell
    - sleep
    - infinity
    image: registry.ci.openshift.org/coreos/coreos-assembler:latest
    name: cosa
    resources:
      requests:
        memory: "6Gi"
        devices.kubevirt.io/kvm: '1'
      limits:
        memory: "6Gi"
        devices.kubevirt.io/kvm: '1'
    volumeMounts:
    - mountPath: /srv
      name: workdir
    securityContext:
      privileged: false
  volumes:
  - name: workdir
    emptyDir: {}
  restartPolicy: Never
```

1. Set the umask

```bash
$ pushd /srv
$ umask 0022
```

1. Init the repo

`$ cosa init https://github.com/openshift/os`

1. Populate the repo files

Determine which repo the failing CI job is using and replicate it.

This can be done by inspecting the results of the failing job and looking for
the portion of the test that uses `curl` to populate the `ocp.repo` (see <https://github.com/openshift/os/blob/master/ci/prow-build-test-qemu.sh#L35>).

For example:

`$ curl -Ls http://base-4-11-rhel8.ocp.svc.cluster.local > src/config/ocp.repo`

1. Build and test normally
