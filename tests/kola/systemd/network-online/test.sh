#!/bin/bash
## kola:
##   description: Verify that network-online.target doesn't block login
##   tags: platform-independent
##   # this really shouldn't take long; if it does, it's that we're hitting the
##   # very issue we're testing for
##   timeoutMin: 3

# https://github.com/openshift/os/pull/1279
# https://issues.redhat.com/browse/OCPBUGS-11124

set -euo pipefail

. $KOLA_EXT_DATA/commonlib.sh

# The fact that we're here means that logins must be working since kola was able
# to SSH to start us. But let's do some sanity-checks to verify that the test
# was valid.

# verify that ovs-configuration is still activating
if [[ $(systemctl show ovs-configuration.service -p ActiveState) != "ActiveState=activating" ]]; then
  systemctl status ovs-configuration.service
  fatal "ovs-configuration.service isn't activating"
fi

if [[ $(systemctl show network-online.target -p ActiveState) != "ActiveState=inactive" ]]; then
  systemctl status network-online.target
  fatal "network-online.target isn't inactive"
fi

echo "ok network-online.target does not block login"
