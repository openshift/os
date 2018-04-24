FROM centos:7 AS base

COPY ostree-master.repo /etc/yum.repos.d/
COPY . /srv/tree/

RUN yum install -y rpm-ostree

RUN cd /srv/tree/ && mkdir build-repo && \
    ostree --repo=build-repo init --mode=bare-user && \
    mkdir repo && \
    ostree --repo=repo init --mode=archive

FROM base

RUN cd /srv/tree && \
    rpm-ostree compose tree --repo=/srv/tree/build-repo host.json && \
    ostree --repo=repo pull-local build-repo openshift/7/x86_64/standard && \
    ostree --repo=repo summary -u && \
    rm -rf build-repo