#!/usr/bin/env bash

set -xe

# See machineid-compat in host-base.yaml.
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
rm -rf /etc/rc.d/init.d/network /etc/rc.d/rc*.d/*network

# And readahead https://bugzilla.redhat.com/show_bug.cgi?id=1594984
# It's long dead upstream, we definitely don't want it.
rm -f /usr/lib/systemd/systemd-readahead /usr/lib/systemd/system/systemd-readahead-*

# We're not using resolved yet
rm -f /usr/lib/systemd/system/systemd-resolved.service

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
