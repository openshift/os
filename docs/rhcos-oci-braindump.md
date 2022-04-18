# RHCOS OCI Image Build Notes

Given some new developments and discoveries about the OpenShift CI system, it is
now possible to build an RHCOS OS image as an OCI-native image.

This relies on a couple of specific behaviors within Buildah, OpenShift Image
Builds (aka OpenShift Builder), and the OpenShift CI system. This document aims
to highlight those behaviors and provide an overall braindump and explainer of
what makes this possible.

## Components

### CoreOS Assembler aka `COSA`

[COSA](https://github.com/coreos/coreos-assembler) is capable of producing an
OCI image version of a given CoreOS build. It does this by generating an OCI
archive within the current COSA build directory, in addition to a QEMU `.qcow2` file.
Within a classic CI system (e.g., Jenkins), one could use a tool such as Skopeo
to copy this OCI archive to an arbitrary container registry. In fact, COSA even
provides a small wrapper around Skopeo which [does exactly
that](https://github.com/coreos/coreos-assembler/blob/main/src/cmd-push-container).
However, because the OpenShift CI system is intended to produce an image and
push it to an OpenShift ImageStream, we cannot easily take advantage of this
mechanism.

Another pitfall is that by default, OpenShift will run a [container with a
randomized user ID to enhance
security](https://cloud.redhat.com/blog/a-guide-to-openshift-and-uids). When a
container runs as an unprivileged user (e.g., `USER noprivs`), this causes
permission issues because the `/etc/passwd` file does not have a matching user
ID. This is relevant to COSA because the coreos-assembler container [runs as an
unprivileged default
user](https://github.com/coreos/coreos-assembler/blob/main/Dockerfile#L36)
(`builder`).

To work around that, we must get the current (randomized) user ID and add that
to the `/etc/passwd` file before running the test. This is accomplished by
[set-openshift-user.sh](https://github.com/openshift/os/blob/master/ci/set-openshift-user.sh).

### OpenShift CI aka `ci-operator`

To produce a container image, the OpenShift CI system uses the [OpenShift Image
Builds](https://docs.openshift.com/container-platform/4.10/cicd/builds/understanding-image-builds.html)
mechanism. In particular, it makes use of the [default Docker Build
strategy](https://docs.openshift.com/container-platform/4.10/cicd/builds/build-strategies.html#builds-strategy-docker-build_build-strategies)
which imposes several limitations on CoreOS builds. Chief amongst those
limitations is that the OpenShift CI system (aka `ci-operator`) does not
completely expose the OpenShift Image Builder API. This is fine for almost all
of OpenShift engineering team use-cases because most teams are building and
shipping software in containers.

An interesting observation was made when using a wildcard to specify resources
for builds and tests:

```yaml
resources:
  '*':
    requests:
      cpu: 2000m
      memory: 3Gi
```

Image builds would request these resources instead of their default values. This
is especially important for the COSA build because it is a very CPU / memory
intensive process.

### OpenShift Image Builds

As mentioned above, OpenShift CI uses the OpenShift Image Builds to build
containers which go through its opinionated release and promotion mechanism. To
elaborate further, we cannot, for example, mount secrets or expose `/dev/kvm` to
the build context.

However, OpenShift CI does expose the [image source build
input](https://docs.openshift.com/container-platform/4.10/cicd/builds/creating-build-inputs.html#builds-image-source_creating-build-inputs)
mechanism. This allows one to inject an arbitrary path from a pre-built
container into the build context of another container.

In particular, OpenShift Image Builds does this by creating a temporary directory at `/tmp/build/inputs/<relative
path>` for each image input ([source](https://github.com/openshift/builder/blob/37525a77fa07e26c420962dee47193d672ef0b35/pkg/build/builder/common.go#L72)) and parsing the Dockerfile to replace any references to the relative path with the absolute path. 

### Buildah

Normally, when the image build is started, any files within the build context
(modulo ones ignored by `.dockerignore`) are copied into the build context and
any files created / modified within the build context are placed there. In other
words, the build context cannot directly mutate the source directory.

However, as of Buildah v1.24, one can [bind-mount an arbitrary path](https://github.com/containers/buildah/pull/3548) on the host into the build context. This is meant to provide parity with BuildKit's capabilities. For example:

```Dockerfile
FROM registry.fedoraproject.org/fedora:latest
RUN --mount=type=bind,rw=true,src=.,dst=/buildcontext,bind-propagation=shared ls -la /buildcontext
```

This bind-mount also enables one to directly mutate the build context source
directory as shown above.

OpenShift Image Builder will use Buildah v1.24 in the OCP 4.11 release. This is
relevant because OpenShift CI will eventually upgrade to this version, however
as of this writing, it is not using that release.

Independent of this capability, Buildah allows one to specify `oci-archive:` as
[an image transport](https://www.redhat.com/sysadmin/7-transports-features).
What this means is that if one has an OCI archive someplace within the build
context, an image can be created from it thusly:

```Dockerfile
FROM oci-archive:/path/to/oci-archive/in/build/context
```

## Putting It Together

### Current Solution

```yaml
# OpenShift CI Config
images:
- dockerfile_literal: |
    FROM build-test-qemu-img:latest
    ENV COSA_DIR=/tmp/cosa
    RUN mkdir -p "${COSA_DIR}" && \
      COSA_NO_KVM=1 /src/ci/prow-build.sh && \
      rm -rf "$COSA_DIR/cache"
  inputs:
    build-test-qemu-img:
      as:
      - build-test-qemu-img:latest
  to: cosa-build
- dockerfile_literal: |
    FROM oci-archive:/tmp/build/inputs/magic/cosa/builds/latest/x86_64/rhcos.x86_64.ociarchive
  inputs:
    cosa-build:
      as:
      - cosa-build
      paths:
      - destination_dir: magic
        source_path: /tmp/cosa
  to: machine-os-oci-content
```

This works thusly:
1. Build the `build-test-qemu-img` from the `ci/Dockerfile` present in this
repository. This copies in all of the scripts and configs as well as builds the
OS layering test binary. 
1. We build the `cosa-build` container which
effectively takes the `build-test-qemu-img` and runs `cosa fetch && cosa build`
as part of a container image build. This produces the OCI archive within
`$COSA_DIR/builds/latest/x86_64/rhcos.ociarchive`.
1. We use this image as the input for the `machine-os-oci-content` image. 

A downside of this mechanism is that the resulting container size for
`cosa-build` is 20+ GB on-disk when the resulting on-disk size of the RHCOS OCI
image is ~2.75 GB.

### Near-Future Solution

Using OCP 4.11 (which uses Buildah v1.24), we can do all of this in a single image build:

```yaml
# OpenShift CI Config
images:
- dockerfile_literal: |
    FROM build-test-qemu-img:latest
    ENV COSA_DIR=/tmp/cosa
    RUN mkdir -p "${COSA_DIR}" && \
      COSA_NO_KVM=1 /src/ci/prow-build.sh && \
      rm -rf "$COSA_DIR/cache"

    # We copy the built OCI archive into the mounted build context.
    RUN --mount=type=bind,rw=true,src=.,dst=/buildcontext,bind-propagation=shared cp "${COSA_DIR}/builds/latest/x86_64/rhcos.x86_64.ociarchive" "/buildcontext/rhcos.x86_64.ociarchive"
  
    # Since we can mutate the build context and we know where the OpenShift
    # Image Builder injects it into the build pod, we can take advantage of the
    # mutated build context thusly.
    FROM oci-archive:/tmp/build/inputs/magic/cosa/builds/latest/x86_64/rhcos.x86_64.ociarchive
  inputs:
    build-test-qemu-img:
      as:
      - build-test-qemu-img:latest
      paths:
      - destination_dir: magic
        # Nothing actually has to exist here; we're just making the image
        # builder aware of a directory within the build context that we expect
        # to be there.
        source_path: /tmp
  to: machine-oci-os-content
```

What is nice about the future solution is that we can largely bypass having to pass around a 20+ GB image since the final image will be around 2.75 GB or so. 

### Far-Future Solution

Building and testing the base image is an expensive process. At the time of this
writing, the periodic and PR jobs are essentially the same with the major
difference being that the periodic builds do not promote an image, whereas the
periodic builds will promote the built image to the `rhcos-devel` namespace.

A future iteration should enable PR builds to consume the nightly-built image
and layer changes introduced by the PR via an image build, which should
substantially reduce the overall build / test time as well as be much less
computationally expensive.

However, doing this will require some retooling within COSA.
