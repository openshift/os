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

NOTE: this is not actually how the pipeline builds
artifacts. The canonical way to build RHCOS are in the
`Jenkinsfile.*` pipeline files. The basic idea of `rdgo`,
`rpm-ostree compose tree`, then `imagefactory` is the same
though.

Right now, each of the `make` targets below are
"independent" of each other, rather than one feeding off the
output of the previous. So additional work is required to
re-use content.

Correspondingly, you don't have to run all of the targets.
E.g. running `make rpmostree-compose` by default will use
the latest RPMs. To make it instead use the RPMs from a
`make rdgo`, one must create a repo file pointing to rdgo's
`build/` dir and add the repo name to `host.yaml`.

- Clone `openshift/os`
- Move into the cloned repo
- Build packages from source repos: `make rdgo`
- Make the ostree: ``make rpmostree-compose``
- Make the qcow2: `make os-image`
    - Requires virtualization. For simplicity, it's easier
      to run this outside a container rather than inside.
      See also
      https://github.com/cgwalters/coreos-assembler/issues/7.
    - This takes a `OSTREE_INSTALL_URL` arg which should be
      a URL to either the internal RHCOS OSTree repo or a
      repo you previously built with `make
      rpmostree-compose`.
    - In many cases, it's much easier to instead build an
      OSTree and then use an existing RHCOS image and
      `rpm-ostree rebase` to the built OSTree. You only need
      to build images if e.g. you make modifications to
      `cloud.ks` or the TDL. (For ignition, one can force it
      to rerun after the first boot by playing with the
      kernel cmdline, deleting `/etc/machine-id`, etc...)

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
