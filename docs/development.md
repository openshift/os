# Notes about development and debugging

To build and test SCOS or RHCOS, see [Building SCOS](development-scos.md) and
[Building RHCOS](development-rhcos.md).

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

`$ curl --fail -Ls http://base-4-11-rhel8.ocp.svc.cluster.local > src/config/ocp.repo`

1. Build and test normally
