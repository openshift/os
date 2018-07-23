# Use fedora as we maintain our tools a bit better there
FROM quay.io/cgwalters/coreos-assembler AS build

COPY RPM-GPG-KEY-* /etc/pki/rpm-gpg/
COPY . /srv/build/

RUN rpm -q rpm-ostree && rpm-ostree --version && \
    cd /srv/build && make repo-refresh && make rpmostree-compose && \
    rm -rf build-repo

# Now inject this content into a new container
FROM registry.centos.org/centos/centos:7
ARG OS_VERSION="3.10-7.5"
ARG OS_COMMIT="null"
LABEL io.openshift.os-version = "$OS_VERSION" \
      io.openshift.os-commit = "$OS_COMMIT"
RUN yum install -y epel-release && yum -y install nginx && yum clean all
# Keep this in sync with Dockerfile.rollup.in
COPY --from=build /srv/build/repo /srv/repo/
COPY nginx.conf /etc/nginx/nginx.conf
COPY index.html subdomain.css /srv/repo/
EXPOSE 8080
CMD ["nginx", "-c", "/etc/nginx/nginx.conf"]
