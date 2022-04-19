#!/bin/bash

# This script is used to update the /etc/passwd file within the COSA container
# at test-time. The need for this comes from the fact that OpenShift will run a
# container with a randomized user ID by default to enhance security. Because
# COSA runs with an unprivileged user ("builder") instead of (container) root,
# this presents special challenges for file and disk permissions. This particular
# pattern was inspired by:
# - https://cloud.redhat.com/blog/jupyter-on-openshift-part-6-running-as-an-assigned-user-id
# - https://cloud.redhat.com/blog/a-guide-to-openshift-and-uids

set -xeuo

user_id="$(id -u)"
group_id="$(id -g)"

cat /etc/passwd | grep -v "^builder" > /tmp/passwd
echo "builder:x:${user_id}:${group_id}::/home/builder:/bin/bash" >> /tmp/passwd
cat /tmp/passwd > /etc/passwd
rm /tmp/passwd

# Not strictly required, but nice for debugging.
id
whoami
