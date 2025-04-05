#!/bin/bash
## kola:
##   tags: "needs-internet"
##   timeoutMin: 30
##   # We've seen some OOM when 1024M is used in similar tests:
##   # https://github.com/coreos/fedora-coreos-tracker/issues/1506
##   minMemory: 2048
##   description: Verify replacing the current kernel with an
##     older centos kernel and replacing with kernel-rt.

set -euo pipefail

. $KOLA_EXT_DATA/commonlib.sh

# Execute a command verbosely, i.e. echoing its arguments to stderr
runv () {
    ( set -x ; "${@}" )
}

basearch=$(arch)

case "${AUTOPKGTEST_REBOOT_MARK:-}" in
"")
    major=$(. /usr/lib/os-release && echo "${CPE_NAME}" | grep -Eo '[0-9]{1,2}')
    case "${major}" in
        9)
            repo_name=c9s.repo
            if [ ! -e /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-Official ]; then
                runv curl -sSLf https://centos.org/keys/RPM-GPG-KEY-CentOS-Official-SHA256 -o /etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-Official
            fi
            ;;
        10)
            repo_name=c10s.repo
            if [ ! -e /etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial-SHA256 ]; then
                runv curl -sSLf https://centos.org/keys/RPM-GPG-KEY-CentOS-Official-SHA256 -o /etc/pki/rpm-gpg/RPM-GPG-KEY-centosofficial-SHA256
            fi
            ;;
        *)  fatal "Unhandled major RHEL/SCOS VERSION=${major}"
            ;;
    esac

    # setup repos
    runv rm -rf /etc/yum.repos.d/*
    runv cp "$KOLA_EXT_DATA/$repo_name" /etc/yum.repos.d/cs.repo
    # Disable all repos except baseos and appstream as not all of them have support for all RHCOS/SCOS supported architectures
    runv sed -i 's/enabled=1/enabled=0/g' /etc/yum.repos.d/cs.repo
    runv sed -i '/\[baseos\]/,/^ *\[/ s/enabled=0/enabled=1/' /etc/yum.repos.d/cs.repo
    runv sed -i '/\[appstream\]/,/^ *\[/ s/enabled=0/enabled=1/' /etc/yum.repos.d/cs.repo

    evr=-$(dnf repoquery kernel --qf '%{EVR}' | grep -v "$(rpm -q kernel --qf %{EVR})" | tail -n1)

    echo "Testing overriding with CentOS Stream kernel"
    runv rpm-ostree override replace --experimental --from repo=baseos kernel{,-core,-modules,-modules-extra,-modules-core}"${evr}"
    runv /tmp/autopkgtest-reboot 1
    ;;
1)
    case $(rpm -qi kernel-core | grep Vendor) in
        *"CentOS")
            echo "ok kernel override"
            ;;
        *)
            runv uname -r
            runv rpm -qi kernel-core
            fatal "Failed to apply kernel override"
            ;;
    esac

    echo "Testing overriding with CentOS Stream RT kernel"
    case $basearch in
        x86_64)
            # Enable nfv and rt repos
            runv sed -i '/\[nfv\]/,/^ *\[/ s/enabled=0/enabled=1/' /etc/yum.repos.d/cs.repo
            runv sed -i '/\[rt\]/,/^ *\[/ s/enabled=0/enabled=1/' /etc/yum.repos.d/cs.repo
            runv rpm-ostree override reset -a
            kernel_pkgs=("kernel-rt-core" "kernel-rt-modules" "kernel-rt-modules-extra" "kernel-rt-modules-core")
            args=()
            for x in ${kernel_pkgs}; do
                args+=(--install "${x}")
            done
            runv rpm-ostree override remove kernel{,-core,-modules,-modules-extra,-modules-core} "${args[@]}"
            runv /tmp/autopkgtest-reboot 2
            ;;
        *) echo "note: no kernel-rt for $basearch"; exit 0
            ;;
    esac
    ;;
2)
    case $(uname -r) in
        *".${basearch}+rt") echo "ok kernel-rt" ;;
        *)
           uname -r
           rpm -q kernel-rt
           fatal "Failed to apply rt kernel override"
        ;;
    esac
    ;;
*)
    fatal "Unhandled reboot mark ${AUTOPKGTEST_REBOOT_MARK:-}"
    ;;
esac

echo ok
