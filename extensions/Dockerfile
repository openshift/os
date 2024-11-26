## Downloads the extensions given the extensions.yaml
FROM registry.ci.openshift.org/rhcos-devel/rhel-coreos:latest as os
# Expects os to be cloned and this build run from the top level dir like:
# podman build -f extensions/Dockerfile .
# also expects submodules to be initialized
RUN mkdir /os
WORKDIR /os
ADD . .
ARG COSA
ARG VARIANT
RUN if [[ -z "$COSA" ]] ; then ci/get-ocp-repo.sh ; fi
# On SCOS, we need to add the GPG keys of the various SIGs we need
RUN if rpm -q centos-stream-release; then \
        if [[ $(rpm -q --qf "%{VERSION}" centos-stream-release) == "9.0" ]]; then \
            if ! rpm -q centos-release-cloud; then \
                dnf install -y centos-release-{cloud,nfv,virt}-common; \
            fi && \
            mkdir -p /usr/share/distribution-gpg-keys/centos && \
            ln -s /etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial /usr/share/distribution-gpg-keys/centos/RPM-GPG-KEY-CentOS-Official && \
            ln -s {/etc/pki/rpm-gpg,/usr/share/distribution-gpg-keys/centos}/RPM-GPG-KEY-CentOS-SIG-Cloud && \
            ln -s {/etc/pki/rpm-gpg,/usr/share/distribution-gpg-keys/centos}/RPM-GPG-KEY-CentOS-SIG-Extras-SHA512 && \
            ln -s {/etc/pki/rpm-gpg,/usr/share/distribution-gpg-keys/centos}/RPM-GPG-KEY-CentOS-SIG-NFV && \
            ln -s {/etc/pki/rpm-gpg,/usr/share/distribution-gpg-keys/centos}/RPM-GPG-KEY-CentOS-SIG-Virtualization ; \
        fi ; \
    fi
RUN if [[ -n "${VARIANT}" ]]; then \
        MANIFEST="manifest-${VARIANT}.yaml"; \
        EXTENSIONS="extensions-${VARIANT}.yaml"; \
    else \
        MANIFEST="manifest.yaml"; \
        EXTENSIONS="extensions.yaml"; \
    fi && \
    rpm-ostree compose extensions --rootfs=/ --output-dir=/usr/share/rpm-ostree/extensions/ ./"${MANIFEST}" ./"${EXTENSIONS}"

## Creates the repo metadata for the extensions.
## This uses Fedora as a lowest-common-denominator because it will work on
## current p8/s390x. See https://github.com/openshift/os/issues/1000
FROM quay.io/fedora/fedora:40 as builder
COPY --from=os /usr/share/rpm-ostree/extensions/ /usr/share/rpm-ostree/extensions/
RUN rm -f /etc/yum.repos.d/*.repo \
&& curl -L https://raw.githubusercontent.com/coreos/fedora-coreos-config/testing-devel/fedora-archive.repo -o /etc/yum.repos.d/fedora-archive.repo
RUN dnf install -y createrepo_c
RUN createrepo_c /usr/share/rpm-ostree/extensions/

## Final container that has the extensions repo dir
FROM registry.access.redhat.com/ubi9/ubi:latest
COPY --from=builder /usr/share/rpm-ostree/extensions/ /usr/share/rpm-ostree/extensions/
