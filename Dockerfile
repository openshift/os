# Use fedora as we maintain our tools a bit better there
FROM quay.io/cgwalters/coreos-assembler AS build

COPY RPM-GPG-KEY-* /etc/pki/rpm-gpg/
COPY . /srv/tree/

RUN cd /srv/tree && make repo-refresh && make rpmostree-compose && \
    rm -rf build-repo

# Now inject this content into a new container
FROM registry.centos.org/centos/centos:7
RUN yum install -y epel-release && yum -y install nginx && yum clean all
COPY --from=build /srv/tree /srv/tree
COPY nginx.conf /etc/nginx/nginx.conf
COPY index.html subdomain.css /srv/tree/repo/
EXPOSE 8080
CMD ["nginx", "-c", "/etc/nginx/nginx.conf"]
