#!/bin/bash
## kola:
##   description: Verify SELinux policy is rebuilt on 8.[0-6] 
##     on first boot.
##     https://issues.redhat.com/browse/OCPBUGS-595
##     https://github.com/openshift/os/pull/962

set -xeuo pipefail

. $KOLA_EXT_DATA/commonlib.sh

cd $(mktemp -d)
journalctl -b -u rhcos-selinux-policy-upgrade > logs.txt
RHEL_VERSION=$(. /usr/lib/os-release && echo ${RHEL_VERSION:-})
echo "RHEL_VERSION=${RHEL_VERSION:-}"
service_should_start=0
case "${RHEL_VERSION:-}" in
  8.[0-6]) service_should_start=1;;
  *) ;;
esac

case "${AUTOPKGTEST_REBOOT_MARK:-}" in
    "")
    if grep -qFe 'Recompiling policy' logs.txt; then
        cat logs.txt
        fatal "Recompiled policy on first boot"
    fi
    setsebool -P container_manage_cgroup on
    /tmp/autopkgtest-reboot changed-policy
    ;;
    "changed-policy")
    if test "${service_should_start}" = "1" && ! grep -qFe 'Recompiling policy' logs.txt; then
        cat logs.txt
        fatal "Failed to recompile policy on first boot"
    fi
    ;;
esac
echo ok
