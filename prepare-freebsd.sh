#!/bin/sh
set -eu
umask 077

SCRIPT_NAME="prepare-freebsd.sh"
[ "$(id -u)" -eq 0 ] || { echo "Run with sudo." >&2; exit 1; }
[ "$(uname -s)" = "FreeBSD" ] || { echo "This script supports FreeBSD only." >&2; exit 1; }

CALLER="${SUDO_USER:-root}"
CALLER_HOME="$(pw usershow "$CALLER" | cut -d: -f9)"
STAGED="$CALLER_HOME/$SCRIPT_NAME"
[ -f "$STAGED" ] || { echo "Download this script to $STAGED before running it." >&2; exit 1; }
id cloud >/dev/null 2>&1 || { echo "Required build user 'cloud' does not exist." >&2; exit 1; }

MAJOR="$(freebsd-version -u | cut -d. -f1)"
case "$MAJOR" in 13|14) ;; *) echo "Supported FreeBSD releases: 13 and 14." >&2; exit 1 ;; esac

echo "Preparing FreeBSD $(freebsd-version -u) VMware golden image..."
env ASSUME_ALWAYS_YES=yes pkg update -f
env ASSUME_ALWAYS_YES=yes pkg install cloud-init open-vm-tools-nox11 sudo
pw groupmod wheel -m cloud

sysrc vmware_guestd_enable=YES
sysrc vmware_kmod_enable=YES 2>/dev/null || true
sysrc hostname=freebsd
hostname freebsd
for service_name in cloudinitpre cloudinit cloudconfig cloudfinal; do
  if service "$service_name" rcvar >/dev/null 2>&1; then
    service "$service_name" enable
  fi
done

mkdir -p /usr/local/etc/cloud/cloud.cfg.d
cat > /usr/local/etc/cloud/cloud.cfg.d/99-vmware-guestinfo.cfg <<'EOF'
datasource_list: [ VMware, NoCloud, None ]
EOF
sed -i '' '/^[[:space:]]*disable_vmware_customization:/d' /usr/local/etc/cloud/cloud.cfg
printf '\ndisable_vmware_customization: false\n' >> /usr/local/etc/cloud/cloud.cfg

cloud-init clean --logs --seed 2>/dev/null || cloud-init clean --logs
rm -rf /var/lib/cloud/instances/* /var/lib/cloud/seed/* 2>/dev/null || true
rm -f /etc/ssh/ssh_host_*
rm -f /etc/hostid
sync

rm -P -f "$STAGED" 2>/dev/null || rm -f "$STAGED"
echo "Preparation complete. The VM will shut down now. Do not boot the master again."
shutdown -p now
