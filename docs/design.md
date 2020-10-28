# Design

This repository was created from a proposal henceforth referred to as
"Content distribution and OTA in converged platform" or just "OTA proposal".

It calls for having a “host image”; we’re using this term to differentiate from
container images. This model covers the Container Linux-style partitions as well
as OSTree or any similar technologies. Currently the plan is to move forward
with the rpm-ostree code; that still leaves a lot of options on the table for
how everything works end-to-end. Today, RHEL Atomic Host is generated inside the
RH firewall using pungi which calls out to Koji which runs rpm-ostree. Then
ostree is served on the wire as a transport, stored in the CDN (Akamai). Prior
to the CoreOS acquisition the plan was to move to “rojig” - embedding a host
image inside RPMs.

Yet another possibility is to skip rojig for now, and simply embed an OSTree
repository inside a container image. This content could then be provided to
nodes via a simple embedded static webserver.

rpm-ostree requires privileged containers today. This is also true of other
processes involved in generating host content such as lorax which is used to
create the installer ISO (which is today then used to build cloud images).

Initially, we can avoid scoping in building an installer image here - we can
reuse the Anaconda from Fedora/RHEL (whichever is being used) as a way to
generate VM/cloud images.

If we’re just going for a POC, we can even avoid generating cloud images, and
use existing ones to bootstrap, or go with a “mutate and snapshot approach”
although that has a lot of pitfalls as a long term solution.

Going back to rpm-ostree; there are two models for embedding the content inside
an image. First, we can generate it outside of a build as a privileged pod
running as a Kube Job, and then trigger a container build which aggregates it
(i.e. download via curl).

The second model is to do a direct container build - that's what the `Dockerfile`
in this repository is doing today.
