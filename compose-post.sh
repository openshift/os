#!/usr/bin/env bash

set -xe

# bin+sbin unification; this is the case on e.g. Arch
# today, and it helps the kola tool which does direct
# SSH; don't need to worry about "is /sbin in root's path".
#
# First, handle any sbin -> bin symlinks, including
# ones which cross names, like /usr/sbin/ping6 -> /usr/bin/ping
for sbin in /usr/sbin/*; do
    if ! test -L ${sbin}; then
        continue
    fi
    bn=$(basename ${sbin})
    bin=/usr/bin/${bn}
    if ! [ -e "${bin}" ]; then
        continue
    fi
    sbin_real=$(realpath ${sbin})
    bin_real=$(realpath ${bin})
    if [ "${bin_real}" = "${sbin_real}" ]; then
        echo "sbin -> bin: ${bin_real} ${sbin_real}"
        rm -f ${sbin}
    fi
done
# Now walk over all files in sbin and move them,
# this time handling any bin -> sbin links
for sbin in /usr/sbin/*; do
    bn=$(basename ${sbin})
    bin=/usr/bin/${bn}
    if test -L ${bin}; then
       target=$(realpath ${bin})
       if [ "${target}" = "${sbin}" ]; then
           rm -f ${bin}
       fi
    fi
    mv -n ${sbin} ${bin}
done
rmdir /usr/sbin
ln -sr /usr/bin /usr/sbin

# See machineid-compat in host.yaml.
# Since that makes presets run on boot, we need to have our defaults in /usr
ln -sfr /usr/lib/systemd/system/{multi-user,default}.target

# This is fixed in post-RHEL7 systemd
ln -sf ../tmp.mount /usr/lib/systemd/system/local-fs.target.wants

# The loops below are too spammy otherwise...
set +x

# Persistent journal by default, because Atomic doesn't have syslog
echo 'Storage=persistent' >> /etc/systemd/journald.conf

# See: https://bugzilla.redhat.com/show_bug.cgi?id=1051816
# and: https://bugzilla.redhat.com/show_bug.cgi?id=1186757
# Keep this in sync with the `install-langs` in the treefile JSON
KEEPLANGS="
en_US
"

# Filter out locales from glibc which aren't UTF-8 and in the above set.
# TODO: https://github.com/projectatomic/rpm-ostree/issues/526
localedef --list-archive | while read locale; do
    lang=${locale%%.*}
    lang=${lang%%@*}
    if [[ $locale != *.utf8 ]] || ! grep -q "$lang" <<< "$KEEPLANGS"; then
        localedef --delete-from-archive "$locale"
    fi
done

set -x

cp -f /usr/lib/locale/locale-archive /usr/lib/locale/locale-archive.tmpl
build-locale-archive

# https://github.com/openshift/os/issues/96
# sudo group https://github.com/openshift/os/issues/96
echo '%sudo        ALL=(ALL)       NOPASSWD: ALL' > /etc/sudoers.d/coreos-sudo-group

# Nuke network.service from orbit
# https://github.com/openshift/os/issues/117
rm /etc/rc.d/init.d/network
rm /etc/rc.d/rc*.d/*network

# And readahead https://bugzilla.redhat.com/show_bug.cgi?id=1594984
# It's long dead upstream, we definitely don't want it.
rm -f /usr/lib/systemd/systemd-readahead /usr/lib/systemd/system/systemd-readahead-*

# Let's have a non-boring motd, just like CL (although theirs is more subdued
# nowadays compared to early versions with ASCII art).  One thing we do here
# is add --- as a "separator"; the idea is that any "dynamic" information should
# be below that.
cat > /etc/motd <<EOF
Red Hat CoreOS
  Information: https://url.corp.redhat.com/redhat-coreos
  Bugs: https://github.com/openshift/os
---

EOF
