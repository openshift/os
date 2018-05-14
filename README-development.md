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
