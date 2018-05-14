FROM centos:7 AS base

COPY RPM-GPG-KEY-redhat-release /etc/pki/rpm-gpg/RPM-GPG-KEY-redhat-release
COPY ostree-master.repo ignition.repo /etc/yum.repos.d/
COPY . /srv/tree/

RUN yum install -y rpm-ostree epel-release && \
    yum install -y nginx

COPY nginx.conf /etc/nginx/nginx.conf

RUN cd /srv/tree && make init-ostree-repo

FROM base

RUN cd /srv/tree && make rpmostree-compose && \
    rm -rf build-repo

COPY index.html subdomain.css /srv/tree/repo/

CMD ["nginx", "-c", "/etc/nginx/nginx.conf"]
