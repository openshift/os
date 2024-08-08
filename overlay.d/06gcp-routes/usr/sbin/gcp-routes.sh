#!/bin/bash

# Update nftables rules based on google cloud load balancer VIPS
#
# This is needed because the GCP L3 load balancer doesn't actually do DNAT;
# the destination IP address is still the VIP. Normally, there is an agent that
# adds the vip to the local routing table, tricking the kernel in to thinking
# it's a local IP and allowing processes doing an accept(0.0.0.0) to receive
# the packets. Clever.
#
# We don't do that. Instead, we DNAT with conntrack. This is so we don't break
# existing connections when the vip is removed. This is useful for draining
# connections - take ourselves out of the vip, but service existing conns.
#
# Additionally, clients can write a file to /run/gcp-routes/$IP.down to force
# a VIP as down. This is useful for graceful shutdown / upgrade.

set -e

# the list of load balancer IPs that are assigned to this node
# keys = values, for easy searching
declare -A vips

curler() {
   curl --silent -L -H "Metadata-Flavor: Google" "http://metadata.google.internal/computeMetadata/v1/instance/${1}"
}

TABLE_NAME="gcp-vips"
EXTERNAL_VIPS_CHAIN="external-vips"
RUN_DIR="/run/gcp-routes"

# Set up base table and rules
initialize() {
    nft -f - <<EOF
        add table ip ${TABLE_NAME} { comment "apiserver loadbalancer routing helper"; }
        add chain ip ${TABLE_NAME} ${EXTERNAL_VIPS_CHAIN} { type nat hook prerouting priority dstnat; comment "gcp LB vip DNAT for external clients"; }
EOF

    mkdir -p "${RUN_DIR}"
}

sync_rules() {
    # Construct the VIP lists. (The nftables syntax allows a trailing comma.)
    external_vips=""
    for vip in "${!vips[@]}"; do
        external_vips="${vip}, ${external_vips}"
    done

    echo "synchronizing VIPs to (${external_vips})"
    {
        echo "flush chain ip ${TABLE_NAME} ${EXTERNAL_VIPS_CHAIN}"
        if [[ -n "${external_vips}" ]]; then
            echo "add rule ip ${TABLE_NAME} ${EXTERNAL_VIPS_CHAIN} ip daddr { ${external_vips} } redirect"
        fi
    } | nft -f -
}

clear_rules() {
    nft delete table ip "${TABLE_NAME}" || true
}

# out parameter: vips
list_lb_ips() {
    for k in "${!vips[@]}"; do
        unset vips["${k}"]
    done

    local net_path="network-interfaces/"
    for vif in $(curler ${net_path}); do
        local hw_addr; hw_addr=$(curler "${net_path}${vif}mac")
        local fwip_path; fwip_path="${net_path}${vif}forwarded-ips/"
        for level in $(curler "${fwip_path}"); do
            for fwip in $(curler "${fwip_path}${level}"); do
                if [[ -e "${RUN_DIR}/${fwip}.down" ]]; then
                    echo "${fwip} is manually marked as down, skipping..."
                else
                    echo "Processing route for NIC ${vif}${hw_addr} for ${fwip}"
                    vips[${fwip}]="${fwip}"
                fi
            done
        done
    done
}

sleep_or_watch() {
    if hash inotifywait &> /dev/null; then
        inotifywait -t 240 -r "${RUN_DIR}" &> /dev/null || true
    else
        # no inotify, need to manually poll
        for (( tries=0; tries<48; tries++ )); do
            for vip in "${!vips[@]}"; do
                if [[ -e "${RUN_DIR}/${vip}.down" ]]; then
                    echo "new downfile detected"
                    break 2
                fi
            done
            sleep 5
        done
    fi
}

case "$1" in
  start)
    initialize
    while :; do
      list_lb_ips
      sync_rules
      echo "done applying vip rules"
      sleep_or_watch
    done
    ;;
  cleanup)
    clear_rules
    ;;
  *)
    echo $"Usage: $0 {start|cleanup}"
    exit 1
esac
