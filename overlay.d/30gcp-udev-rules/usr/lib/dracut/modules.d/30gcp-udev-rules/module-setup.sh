#!/usr/bin/bash
# ATTENTION: This is a copy from https://github.com/GoogleCloudPlatform/guest-configs/blob/37fe937011084e54f4358668bfa151a7184d4555/src/lib/dracut/modules.d/30gcp-udev-rules/module-setup.sh
# Install 65-gce-disk-naming.rules and
# google_nvme_id into the initramfs

# called by dracut
install() {
  inst_multiple nvme grep sed
  inst_simple /usr/lib/udev/google_nvme_id
  inst_simple /usr/lib/udev/rules.d/65-gce-disk-naming.rules
}

installkernel() {
  instmods nvme
}
