# Background

RHCOS is a derivative of both RHEL and Fedora CoreOS.  The tool
to build both RHCOS and FCOS is [coreos-assembler](https://github.com/coreos/coreos-assembler/).
See the upstream documentation there first, and pull down
the container.

coreos-assembler (or "cosa") accepts a configuration git repository
as input.  This repository is that configuration for RHCOS,
just like [fedora-coreos-config](https://github.com/coreos/fedora-coreos-config)
is for FCOS.

For example, you would use
```
$ cosa init https://github.com/openshift/os
```

to start.  However, currently you need to configure
the rpm-md repositories manually:

# Repositories

The RHEL repositories are only available to Red Hat customers,
and it's likely that you want to use a mirror.  And further,
a common scenario is to inject specific versioned rpm-md repositories
to test different snapshots or "composes".  For these reasons,
you need to provide the repos of input RPMs.

To do so, create a `rhcos.repo` file that looks like this:

```
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

## Building RHEL CoreOS in api.ci

The "api.ci" (CI cluster used by OpenShift builds itself) has a service that pulls
internal RHEL repos:
See https://github.com/openshift/release/blob/master/core-services/release-controller/README.md#rpm-mirrors

In addition, as of recently the the "build02" cluster which runs in GCP now supports nested virt;
see https://coreos.github.io/coreos-assembler/working/#running-coreos-assembler-in-openshift-on-google-compute-platform

With the combination of these two, you can now easily build RHCOS there!

Use a web browser to [Log into build02](https://console.build02.ci.openshift.org/) and set up a project for your user (if you haven't already):
```
$ oc new-project $USER
```

Now, create a coreos-assembler pod for yourself:
```
$ cat cosa-pod.yaml
apiVersion: v1
kind: Pod
metadata:
  labels:
    run: cosa
  name: cosa
spec:
  containers:
  - args:
    - shell
    - sleep
    - infinity
    image: quay.io/coreos-assembler/coreos-assembler:latest
    name: cosa
    resources:
      requests:
        memory: "2Gi"
        devices.kubevirt.io/kvm: "1"
      limits:
        memory: "2Gi"
        devices.kubevirt.io/kvm: "1"
    volumeMounts:
    - mountPath: /srv
      name: workdir
  volumes:
  - name: workdir
    emptyDir: {}
  restartPolicy: Never
$ oc create -f cosa-pod.yaml
$ oc rsh pod/cosa
```

Build RHCOS; all the following commands should be in the remote coreos-assembler shell:
```
$ cd /srv
$ cosa init https://github.com/openshift/os
$ curl -L http://base-4-7-rhel8.ocp.svc.cluster.local > src/config/ocp.repo
$ cosa fetch
$ cosa build
```
