#!/usr/bin/env bash

set -e

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
