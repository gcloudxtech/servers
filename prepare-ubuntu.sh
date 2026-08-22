#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_NAME="prepare-ubuntu.sh"
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }
. /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || { echo "This script supports Ubuntu only." >&2; exit 1; }

CALLER="${SUDO_USER:-root}"
CALLER_HOME="$(getent passwd "$CALLER" | cut -d: -f6)"
STAGED="$CALLER_HOME/$SCRIPT_NAME"
[[ -f "$STAGED" ]] || { echo "Download this script to $STAGED before running it." >&2; exit 1; }
id cloud >/dev/null 2>&1 || { echo "Required build user 'cloud' does not exist." >&2; exit 1; }

echo "Preparing Ubuntu ${VERSION_ID:-unknown} VMware golden image..."
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y cloud-init cloud-initramfs-growroot open-vm-tools openssh-server sudo
usermod -aG sudo cloud
systemctl enable open-vm-tools ssh
hostnamectl set-hostname ubuntu

install -d -m 0755 /etc/cloud/cloud.cfg.d
printf '%s\n' \
  'datasource_list: [ VMware, NoCloud, None ]' \
  > /etc/cloud/cloud.cfg.d/99-vmware-guestinfo.cfg
sed -i '/^[[:space:]]*disable_vmware_customization:/d' /etc/cloud/cloud.cfg
printf '\ndisable_vmware_customization: false\n' >> /etc/cloud/cloud.cfg

cloud-init clean --logs --seed
rm -rf /var/lib/cloud/instances/* /var/lib/cloud/seed/*
rm -f /etc/ssh/ssh_host_*
truncate -s 0 /etc/machine-id
rm -f /var/lib/dbus/machine-id
apt-get clean
sync

shred -u "$STAGED" 2>/dev/null || rm -f "$STAGED"
echo "Preparation complete. The VM will shut down now. Do not boot the master again."
shutdown -h now
