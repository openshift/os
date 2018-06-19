# Operating System

## Prerequisites

### Usually packaged by operating systems
- git
- ostree
- rpm-ostree
- qemu-img
- fedpkg
- mock

### May need to be built from source
- [rpmdistro-gitoverlay](https://github.com/projectatomic/rpmdistro-gitoverlay)
- [imagefactory-plugins-TinMan](https://github.com/redhat-imaging/imagefactory)

## Building

Choose a local mirror to use for OSTREE_INSTALL_URL from [the list](https://admin.fedoraproject.org/mirrormanager/mirrors/Fedora/28/x86_64)

- Clone ``openshift/os``
- Move into the cloned repo
- Build packages from source repos: ``make rdgo``
- Make the ostree: ``make rpmostree-compose``
- Make the qcow2: ``make os-image OSTREE_INSTALL_URL=<OSTREE_INSTALL_URL_HERE>``

# Container Image

This repository uses [https://docs.docker.com/develop/develop-images/multistage-build/](multi-stage) builds.
If you're using Project Atomic/RHEL Docker, your best bet is to build [OpenShift imagebuilder](https://github.com/openshift/imagebuilder)
docker.

If you're going to iterate a lot on the host, it's recommended to stand up
a persistent "pet" development container, install `rpm-ostree` inside that,
as well as persistent OSTree repositories.

You'll also want to use the `--cachedir` argument to avoid repeatedly
downloading RPMs. More information in
the [rpm-ostree docs](https://github.com/projectatomic/rpm-ostree/blob/master/docs/manual/compose-server.md).

Example setup (in a container, though /srv should be a persistent mount)
---

```
# mkdir -p /srv/origin-os
# cd /srv/origin-os
# mkdir cache
# git clone https://github.com/openshift/os  (or symlink it from your user's directory)
# (cd os && make repo-refresh)
# ln -s os/Makefile .
# make
```

Iterating more quickly with `--cache-only`:
```
# make COMPOSEFLAGS=--cache-only
```
