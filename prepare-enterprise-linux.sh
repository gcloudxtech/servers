#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

SCRIPT_NAME="prepare-enterprise-linux.sh"
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo "Run with sudo." >&2; exit 1; }
. /etc/os-release
case "${ID:-}" in
  almalinux|rocky|centos|rhel|ol) ;;
  *) echo "Supports AlmaLinux, Rocky Linux, CentOS and RHEL-compatible systems only." >&2; exit 1 ;;
esac

CALLER="${SUDO_USER:-root}"
CALLER_HOME="$(getent passwd "$CALLER" | cut -d: -f6)"
STAGED="$CALLER_HOME/$SCRIPT_NAME"
[[ -f "$STAGED" ]] || { echo "Download this script to $STAGED before running it." >&2; exit 1; }
id cloud >/dev/null 2>&1 || { echo "Required build user 'cloud' does not exist." >&2; exit 1; }

echo "Preparing ${PRETTY_NAME:-Enterprise Linux} VMware golden image..."
PKG=dnf
command -v dnf >/dev/null 2>&1 || PKG=yum
"$PKG" -y install cloud-init open-vm-tools openssh-server sudo
usermod -aG wheel cloud
systemctl enable vmtoolsd sshd cloud-init-local cloud-init cloud-config cloud-final
case "$ID" in
  almalinux) TEMPLATE_HOSTNAME=almalinux ;;
  rocky) TEMPLATE_HOSTNAME=rocky ;;
  rhel) TEMPLATE_HOSTNAME=rhel ;;
  *) TEMPLATE_HOSTNAME=centos ;;
esac
hostnamectl set-hostname "$TEMPLATE_HOSTNAME"

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
"$PKG" clean all
sync

shred -u "$STAGED" 2>/dev/null || rm -f "$STAGED"
echo "Preparation complete. The VM will shut down now. Do not boot the master again."
shutdown -h now
