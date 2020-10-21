This repository is the "config" repository used to build
RHEL CoreOS using [coreos-assembler](https://github.com/coreos/coreos-assembler/).

There was a previous git repository inside the Red Hat
firewall never published.  The history of that repository
is entangled with various private things and is omitted.

Going forward, this repository will be canonical; more
to come.

# Building

You need to create a `rhcos.repo` file that looks like this:

```
# RHEL repos
[rhel8-baseos]
baseurl=<url>

[rhel8-appstream]
baseurl=<url>

[rhel8-nfv]
baseurl=<url>

[rhel8-fast-datapath]
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
$ curl -L http://base-4-7-rhel8.ocp.svc.cluster.local > src/config/ocp.repo
```
