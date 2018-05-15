# Use fedora as we maintain our tools a bit better there
FROM registry.fedoraproject.org/fedora:28 AS build

COPY RPM-GPG-KEY-* /etc/pki/rpm-gpg/
COPY . /srv/tree/

RUN yum install -y make rpm-ostree nginx
COPY nginx.conf /etc/nginx/nginx.conf

RUN cd /srv/tree && make rpmostree-compose && \
    rm -rf build-repo

# Now inject this content into a CentOS-based container
FROM registry.centos.org/centos/centos:7
COPY --from=build /srv/tree /srv/tree
COPY index.html subdomain.css /srv/tree/repo/
CMD ["nginx", "-c", "/etc/nginx/nginx.conf"]
