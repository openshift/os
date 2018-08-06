# This Dockerfile *used* to run rpm-ostree, but
# we now have a custom build process.  We're just
# keeping this Dockerfile around as there's a Prow
# job that looks at it.
FROM registry.fedoraproject.org/fedora:28
