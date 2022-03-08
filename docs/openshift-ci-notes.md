# OpenShift CI Notes

Given the current limitations of the OpenShift CI system, it was decided to
build the RHCOS OS images on a periodic (daily) basis. While the full test
suite will run on each PR as it always has, this test suite will also be run
periodically prior to the images being pushed.

## Where will the images be pushed? How will they be tagged?

In general, the images will be pushed to
`registry.ci.openshift.org/rhcos-devel/rhel-coreos`. Images will have the
following tags:

- `rhel-coreos:latest` - the latest image built from the `master` branch.
- `rhel-coreos:<ocp version>` - the latest image for the associated release branch, starting with `4.11`.
- `rhel-coreos:<build id>-<arch>` - the coreos-assembler build ID and (for now) the architecture.

## How are the secrets configured?

A new secret called `image-pusher-periodic-job-token` was created in the
`rhcos-devel` namespace which is attached to the `image-pusher` service account
which enables images to be pushed to the `rhcos-devel` registry namespace. This
secret is only used for this job.

Following the [OpenShift
CI](https://docs.ci.openshift.org/docs/how-tos/adding-a-new-secret-to-ci/)
instructions, the token was added to Vault and injected into the test
environment at run-time.
