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

## Accessing repos in api.ci

The "api.ci" (CI cluster used by OpenShift builds itself) has a service that pulls
internal RHEL repos:
See https://github.com/openshift/release/blob/master/core-services/release-controller/README.md#rpm-mirrors

Use this:
```
$ cosa init https://github.com/openshift/os
$ curl -L http://base-4-8-rhel8.ocp.svc.cluster.local > src/config/ocp.repo
```

## Updating FCOS

As noted above, RHCOS uses FCOS as an upstream.  This is implemented
by inheriting from the [fedora-coreos-config](https://github.com/coreos/fedora-coreos-config/)
repository as a git submodule; the RHCOS manifests and overlays include parts (though not all)
of FCOS.

After a change is landed in FCOS, it's often OK to also immediately update RHCOS' master
branch to the latest FCOS.  We try to keep things compatible.

```
$ (cd fedora-coreos-config && git fetch origin && git reset --hard origin/testing-devel)
$ git commit -a -m 'Update FCOS'
```
