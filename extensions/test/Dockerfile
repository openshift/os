FROM registry.ci.openshift.org/rhcos-devel/rhel-coreos:latest
#We want to test it's only using the extensions repo
RUN rm -rf /etc/yum.repos.d/*
ADD ext.repo /etc/yum.repos.d/extension.repo
#Install usbguard as provided by the repo
RUN rpm-ostree install usbguard
RUN usbguard
