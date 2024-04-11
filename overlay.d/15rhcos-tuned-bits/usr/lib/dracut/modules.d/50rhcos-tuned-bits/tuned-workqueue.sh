#!/bin/sh
# This file was adapted from
# https://raw.githubusercontent.com/redhat-performance/tuned/584f7dbe2cb56d5ba835450d3372717acc574034/profiles/cpu-partitioning/00-tuned-pre-udev.sh
# See https://gitlab.cee.redhat.com/coreos/redhat-coreos/merge_requests/727
# Basically we want to support the same kernel argument that tuned does,
# until such time as this support lands in systemd itself.

type getargs >/dev/null 2>&1 || . /lib/dracut-lib.sh

function tuned_pre_udev_main() {
  local cpumask="$(getargs tuned.non_isolcpus)"
  local path=/sys/devices/virtual/workqueue/cpumask
  if [ -n "$cpumask" ]; then
    echo "tuned: setting workqueue CPU mask to $cpumask" >> /dev/kmsg
    echo $cpumask > ${path}
  fi
}

tuned_pre_udev_main
