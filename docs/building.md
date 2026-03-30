# Building

## Preparation

Unfortunately, even building the OKD node image currently
[requires access](https://github.com/openshift/os/blob/44326c81951023c0c596c1a7ef3df5f4ebbef2a2/build-node-image.sh#L22-L30)
to internal repos.

This means that the first step is to have access to the necessary
repo files. First, connect to the Red Hat VPN, then clone
[this git repository](https://url.corp.redhat.com/fc84483) containing the
canonical yum repo files used to compose RHEL CoreOS. (Ability to clone
this repo also requires that you have the internal Red Hat IT CA certificate
installed, which is also needed for the build step below.)

Then, combine all the repo files into a single one, e.g.:

```
cat *.repo > all.repo
```

You will also need either
[an OpenShift pull secret](https://console.redhat.com/openshift/install/aws/installer-provisioned)
to be able to pull the base images or a locally built base
SCOS or RHCOS image (see building instructions in
[that repo](https://github.com/coreos/rhel-coreos-config)).

## Building

Each variant has a `build-args-*.conf` file that specifies the base image
and metadata for that build. Choose the appropriate one for your target:

- `build-args-9.8-4.22.conf` — RHCOS on RHEL 9.8
- `build-args-10.2-4.22.conf` — RHCOS on RHEL 10.2
- `build-args-c10s-4.22.conf` — SCOS on CentOS Stream 10

To build:

```
podman build . --build-arg-file build-args-c10s-4.22.conf \
  --secret id=yumrepos,src=/path/to/all.repo \
  -v /etc/pki/ca-trust:/etc/pki/ca-trust:ro \
  --security-opt label=disable -t localhost/stream-coreos:4.22
```

To override the base image (e.g. to use a locally built OCI archive),
pass `--from`:

```
podman build . --build-arg-file build-args-c10s-4.22.conf \
  --from oci-archive:$(ls builds/latest/x86_64/*.ociarchive) \
  --secret id=yumrepos,src=/path/to/all.repo \
  -v /etc/pki/ca-trust:/etc/pki/ca-trust:ro \
  --security-opt label=disable -t localhost/stream-coreos:4.22
```
