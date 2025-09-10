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

If the base image is SCOS, then the OKD node image is built (`stream-coreos`).
If the base image is RHCOS, then the OCP node image is built (`rhel-coreos`).
The default base image is SCOS.

To build SCOS:

```
podman build . --secret id=yumrepos,src=/path/to/all.repo \
  -v /etc/pki/ca-trust:/etc/pki/ca-trust:ro \
  --security-opt label=disable -t localhost/stream-coreos:4.21
```

To build RHCOS, the command is identical, but you must pass in the RHCOS base
image using `--from`:

```
podman build --from quay.io/openshift-release-dev/ocp-v4.0-art-dev:rhel-9.6-coreos ...
```

To build from a local OCI archive (e.g. from a cosa workdir), you can use the
`oci-archive` transport:

```
podman build --from oci-archive:$(ls builds/latest/x86_64/*.ociarchive) ...
```
