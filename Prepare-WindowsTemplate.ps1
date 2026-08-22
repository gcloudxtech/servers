#requires -Version 5.1
#requires -RunAsAdministrator
[CmdletBinding()]
param(
    [string]$CloudbaseMsiUrl = 'https://www.cloudbase.it/downloads/CloudbaseInitSetup_Stable_x64.msi'
)

$ErrorActionPreference = 'Stop'
$ScriptName = 'Prepare-WindowsTemplate.ps1'
$StagedScript = Join-Path $HOME $ScriptName

if (-not (Test-Path -LiteralPath $StagedScript)) {
    throw "Download this script to $StagedScript before running it."
}

$os = Get-CimInstance Win32_OperatingSystem
if ($os.ProductType -eq 1) {
    Write-Warning 'This script is intended for Windows Server, not desktop Windows.'
}

try {
    $null = [ADSI]'WinNT://./cloud,user'
    $null.psbase.InvokeGet('Name')
} catch {
    throw "Required build user 'cloud' does not exist. Create it before running this script."
}
& net.exe localgroup Administrators cloud /add | Out-Null
if ($LASTEXITCODE -notin @(0, 1378)) {
    throw "Could not add 'cloud' to the local Administrators group. Exit code: $LASTEXITCODE"
}

$vmTools = Join-Path $env:ProgramFiles 'VMware\VMware Tools\rpctool.exe'
if (-not (Test-Path -LiteralPath $vmTools)) {
    throw 'VMware Tools is required. Install VMware Tools and rerun this script.'
}

$workDir = Join-Path $env:TEMP 'vmware-template-prep'
$msiPath = Join-Path $workDir 'CloudbaseInitSetup.msi'
New-Item -ItemType Directory -Path $workDir -Force | Out-Null

Write-Host 'Downloading and installing Cloudbase-Init...'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Invoke-WebRequest -Uri $CloudbaseMsiUrl -OutFile $msiPath -UseBasicParsing
$msi = Start-Process msiexec.exe -ArgumentList @('/i', $msiPath, '/qn', '/norestart', '/l*v', (Join-Path $workDir 'cloudbase-init-msi.log')) -Wait -PassThru
if ($msi.ExitCode -notin @(0, 3010)) {
    throw "Cloudbase-Init installation failed with exit code $($msi.ExitCode)."
}

$base = Join-Path $env:ProgramFiles 'Cloudbase Solutions\Cloudbase-Init'
$confDir = Join-Path $base 'conf'
$mainConf = Join-Path $confDir 'cloudbase-init.conf'
$unattendConf = Join-Path $confDir 'cloudbase-init-unattend.conf'
$unattendXml = Join-Path $confDir 'Unattend.xml'

$config = @'
[DEFAULT]
username=cloud
groups=Administrators
inject_user_password=true
first_logon_behaviour=no
allow_reboot=true
metadata_services=cloudbaseinit.metadata.services.vmwareguestinfoservice.VMwareGuestInfoService
plugins=cloudbaseinit.plugins.windows.extendvolumes.ExtendVolumesPlugin,cloudbaseinit.plugins.common.networkconfig.NetworkConfigPlugin,cloudbaseinit.plugins.common.sethostname.SetHostNamePlugin,cloudbaseinit.plugins.common.setuserpassword.SetUserPasswordPlugin,cloudbaseinit.plugins.common.sshpublickeys.SetUserSSHPublicKeysPlugin,cloudbaseinit.plugins.common.userdata.UserDataPlugin
verbose=true
debug=false
logdir=C:\Program Files\Cloudbase Solutions\Cloudbase-Init\log\
logfile=cloudbase-init.log
default_log_levels=comtypes=INFO,suds=INFO,iso8601=WARN,requests=WARN
logging_serial_port_settings=
mtu_use_dhcp_config=true
ntp_use_dhcp_config=true
netbios_host_name_compatibility=false
activate_windows=false
'

if (-not (Test-Path -LiteralPath $confDir)) {
    throw "Cloudbase-Init configuration directory was not found at $confDir"
}
Set-Content -LiteralPath $mainConf -Value $config -Encoding ASCII
Set-Content -LiteralPath $unattendConf -Value $config -Encoding ASCII

Set-Service -Name cloudbase-init -StartupType Automatic
Stop-Service -Name cloudbase-init -Force -ErrorAction SilentlyContinue
Rename-Computer -NewName 'WINDOWS' -Force

if (-not (Test-Path -LiteralPath $unattendXml)) {
    throw "Cloudbase-Init Unattend.xml was not found at $unattendXml"
}

Write-Host 'Cleaning event logs and temporary installer files...'
Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | ForEach-Object {
    try { [System.Diagnostics.Eventing.Reader.EventLogSession]::GlobalSession.ClearLog($_.LogName) } catch {}
}
Remove-Item -LiteralPath $workDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -LiteralPath $StagedScript -Force

Write-Host 'Starting Sysprep. Windows will shut down automatically.'
Write-Host 'Do not boot the master image again.'
Start-Process "$env:SystemRoot\System32\Sysprep\Sysprep.exe" -ArgumentList @('/generalize', '/oobe', '/shutdown', "/unattend:$unattendXml")
