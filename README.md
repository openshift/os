# Demonstration of building a host OSTree as a container image

This project does an [rpm-ostree](https://github.com/projectatomic/rpm-ostree)
build inside a container; that container can then be pulled and run in a cluster,
providing a HTTP server for clients to upgrade.

Locally (but see [README-development.md] for more information on builds)

```
$ docker build .
$ docker push SOME_IMAGE
```

Turn a CentOS Atomic AWS AMI booted machine into this OS:

1. Launch an AMI for CentOS 7 (ami-a06447da) with at least 20GB disk (10GB is too small for now)
2. Resize the disk:

```
$ lvextend -l +25%FREE atomicos/root
$ xfs_growfs /
```

3. SSH to the machine and run:

```
$ docker run --network host -d -w /srv/tree/repo registry.svc.ci.openshift.org/ci/os:test python -m SimpleHTTPServer 8080
$ ostree remote add --no-gpg-verify local http://localhost:8080 openshift/3.10/x86_64/os
$ rpm-ostree rebase -r local:openshift/3.10/x86_64/os

# wait, SSH back in
$ openshift version
```

Within a Kubernetes cluster, serve this content to nodes for upgrades:

```
$ kubectl run os-content --image=registry.svc.ci.openshift.org/ci/os:test --command -- python -m HttpServer 8080
$ kubectl expose os-content --port 8080

$ ssh root@NODE_HOST
$ ostree remote add --no-gpg-verify local http://os-content.namespace.svc:8080 openshift/3.10/x86_64/os
$ rpm-ostree rebase -r local:openshift/3.10/x86_64/os

# wait, SSH back in
$ openshift version
```
