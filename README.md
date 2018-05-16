# Demonstration of delivering OSTree host updates as a container image

This project does an [rpm-ostree](https://github.com/projectatomic/rpm-ostree)
build inside a container; that container can then be pulled and run in a cluster,
providing a HTTP server for clients to upgrade.

Locally (but see [README-development.md] for more information on builds)

```
$ docker build .
$ docker push SOME_IMAGE
```

Turn a [CentOS Atomic](https://wiki.centos.org/SpecialInterestGroup/Atomic/Download) booted machine into this OS:

1. Provision a machine (e.g. an `ami-a06447da` in AWS us-east-1) with at least 20GB disk (10GB is too small for now)
2. Resize the disk:

```
$ lvm lvextend -r -l +25%FREE atomicos/root
```

3. SSH to the machine and run:

```
$ docker run --network host -d -w /srv/tree/repo $REGISTRY/os:latest
$ ostree remote add --no-gpg-verify local http://localhost:8080 openshift/3.10/x86_64/os
$ rpm-ostree rebase -r local:openshift/3.10/x86_64/os

# wait, SSH back in
$ openshift version
```

Within a Kubernetes cluster, serve this content to nodes for upgrades:

```
$ kubectl run os-content --image=$REGISTRY/os:latest
$ kubectl expose os-content --port 8080

$ ssh root@NODE_HOST
$ ostree remote add --no-gpg-verify local http://os-content.namespace.svc:8080 openshift/3.10/x86_64/os
$ rpm-ostree rebase -r local:openshift/3.10/x86_64/os

# wait, SSH back in
$ openshift version
```
