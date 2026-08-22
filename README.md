# VMware GuestInfo Template Preparation Scripts

One-time preparation scripts for clean VMware ESXi golden images that receive
hostname, networking, initial credentials and SSH keys through VMware GuestInfo.
They are designed for standalone ESXi as well as vCenter.

The build VMs use the following temporary local credential:

```text
Username: cloud
Password: Cloud@9999
```

Create that account during OS installation. The preparation scripts verify the
`cloud` user on Unix-family systems but do not recreate it or print its password.
Provisioning metadata should replace the temporary password on first boot.

## Supported families

| Script | Main image variants |
| --- | --- |
| `prepare-ubuntu.sh` | Ubuntu 18.04, 20.04, 22.04, 24.04, 25.x |
| `prepare-debian.sh` | Debian 10, 11, 12, 13 |
| `prepare-enterprise-linux.sh` | AlmaLinux 8/9, Rocky Linux 8/9, CentOS 7/8/Stream, RHEL-compatible 8/9 |
| `prepare-freebsd.sh` | FreeBSD 13 and 14 |
| `Prepare-WindowsTemplate.ps1` | Windows Server 2012 R2, 2016, 2019, 2022 and 2025 |

Older releases may have repositories that are EOL. The scripts stop if required
packages cannot be installed.

## Important warnings

- Run only inside a newly installed VM intended to become a golden image.
- The script cleans machine identity, cloud-init state and SSH host keys.
- The VM shuts down automatically when preparation completes.
- Keep the VM's VMXNET3 NIC installed, but disconnect it before preserving the
  master. Reconnect it and select the destination port group before first boot.
- Leave the fresh installation's NIC configured for DHCP. The preparation
  scripts do not hard-code, remove or disable its network configuration.
- Never power on the cleaned master. Make a copy/deploy it first.
- Take a snapshot or backup before testing these scripts.

## GitHub one-line commands

Replace `YOUR-ORG/YOUR-REPO` and branch if necessary. The command deliberately
downloads the script into the invoking user's home directory before execution.
The script securely removes itself before shutdown.

### Ubuntu

```bash
curl -fL https://raw.githubusercontent.com/YOUR-ORG/YOUR-REPO/main/prepare-ubuntu.sh -o "$HOME/prepare-ubuntu.sh" && chmod 700 "$HOME/prepare-ubuntu.sh" && sudo "$HOME/prepare-ubuntu.sh"
```

### Debian

```bash
curl -fL https://raw.githubusercontent.com/YOUR-ORG/YOUR-REPO/main/prepare-debian.sh -o "$HOME/prepare-debian.sh" && chmod 700 "$HOME/prepare-debian.sh" && sudo "$HOME/prepare-debian.sh"
```

### AlmaLinux, Rocky Linux, CentOS or RHEL-compatible

```bash
curl -fL https://raw.githubusercontent.com/YOUR-ORG/YOUR-REPO/main/prepare-enterprise-linux.sh -o "$HOME/prepare-enterprise-linux.sh" && chmod 700 "$HOME/prepare-enterprise-linux.sh" && sudo "$HOME/prepare-enterprise-linux.sh"
```

### FreeBSD

Use `fetch` from the normal shell:

```sh
fetch -o "$HOME/prepare-freebsd.sh" https://raw.githubusercontent.com/YOUR-ORG/YOUR-REPO/main/prepare-freebsd.sh && chmod 700 "$HOME/prepare-freebsd.sh" && sudo "$HOME/prepare-freebsd.sh"
```

### Windows Server

Open **Windows PowerShell as Administrator** (not PowerShell 7) and run:

```powershell
$u='https://raw.githubusercontent.com/YOUR-ORG/YOUR-REPO/main/Prepare-WindowsTemplate.ps1'; $p=Join-Path $HOME 'Prepare-WindowsTemplate.ps1'; Invoke-WebRequest $u -OutFile $p; Set-ExecutionPolicy Bypass -Scope Process -Force; & $p
```

The Windows script requires VMware Tools. It installs Cloudbase-Init, configures
VMware GuestInfo, deletes itself and starts Sysprep with `/generalize /oobe
/shutdown`.

## GuestInfo keys

Set these after copying/deploying the image and before its first power-on:

```text
guestinfo.metadata
guestinfo.metadata.encoding = base64
guestinfo.userdata
guestinfo.userdata.encoding = base64
```

Use a different `instance-id` for every deployed VM.

The template starts from DHCP. If the provisioning request contains the
`network` section below, cloud-init applies the allocated public static address
on first boot. If no network section is supplied, the deployed VM continues to
use DHCP.

Linux/BSD metadata example:

```yaml
instance-id: ubuntu-10025
local-hostname: ubuntu
network:
  version: 2
  ethernets:
    nic0:
      match:
        macaddress: "00:50:56:aa:bb:cc"
      addresses:
        - 10.10.61.25/24
      routes:
        - to: default
          via: 10.10.61.1
      nameservers:
        addresses: [10.10.61.1, 1.1.1.1]
```

Linux/BSD user-data example:

```yaml
#cloud-config
users:
  - name: cloud
    groups: [sudo]
    shell: /bin/bash
    lock_passwd: false
    passwd: "$6$REPLACE_WITH_SHA512_CRYPT_HASH"
    sudo: ["ALL=(ALL) ALL"]
ssh_pwauth: true
chpasswd:
  expire: true
growpart:
  mode: auto
  devices: [/]
resize_rootfs: true
```

On Enterprise Linux use `groups: [wheel]`. On FreeBSD use `groups: [wheel]`
and `shell: /bin/sh`.

Windows metadata is YAML and can directly carry the initial Administrator
password:

```yaml
instance-id: windows-10025
local-hostname: windows
admin-username: cloud
admin-password: "REPLACE_WITH_TEMPORARY_PASSWORD"
network:
  version: 2
  ethernets:
    nic0:
      match:
        macaddress: "00:50:56:aa:bb:cc"
      addresses: [10.10.61.30/24]
      gateway4: 10.10.61.1
      nameservers:
        addresses: [10.10.61.1, 1.1.1.1]
```

Passwords placed in GuestInfo are configuration secrets, not a secret vault.
Use temporary passwords, restrict ESXi API access, and remove/redact GuestInfo
values after first-boot provisioning.

## Verification after deployment

Linux:

```bash
cloud-init status --wait
sudo cloud-init status --long
```

FreeBSD:

```sh
cloud-init status --wait
```

Windows logs:

```text
C:\Program Files\Cloudbase Solutions\Cloudbase-Init\log\cloudbase-init.log
```
