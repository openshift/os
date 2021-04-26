# For CI on a config git repo, all we need to do is combine
# the source code with coreos-assembler into an image to test.
FROM registry.svc.ci.openshift.org/coreos/coreos-assembler:latest
WORKDIR /src
COPY . .
ENV COSA_SKIP_OVERLAY=1
