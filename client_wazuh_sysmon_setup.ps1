#requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

Write-Host "=== Wazuh Agent + Sysmon Client Setup ==="

$WazuhManager = Read-Host "Wazuh Manager IP/FQDN"
$AgentName = Read-Host "Agent Name [Enter = ComputerName]"
$AgentGroup = Read-Host "Agent Group [Enter = windows,sysmon,misp]"

if ([string]::IsNullOrWhiteSpace($AgentName)) {
    $AgentName = $env:COMPUTERNAME
}

if ([string]::IsNullOrWhiteSpace($AgentGroup)) {
    $AgentGroup = "windows,sysmon,misp"
}

if ([string]::IsNullOrWhiteSpace($WazuhManager)) {
    Write-Host "[ERROR] Wazuh Manager ห้ามว่าง"
    exit 1
}

$TempDir = "$env:TEMP\wazuh_sysmon"
$WazuhMsi = "$TempDir\wazuh-agent.msi"
$SysmonDir = "C:\Program Files\Sysmon"
$SysmonExe = "$SysmonDir\Sysmon64.exe"
$SysmonConfig = "$SysmonDir\sysmonconfig.xml"
$WazuhConf = "C:\Program Files (x86)\ossec-agent\ossec.conf"

$WazuhUrl = "https://packages.wazuh.com/4.x/windows/wazuh-agent-4.14.0-1.msi"
$SysmonUrl = "https://live.sysinternals.com/Sysmon64.exe"
$ConfigUrl = "https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml"

New-Item -ItemType Directory -Force -Path $TempDir | Out-Null
New-Item -ItemType Directory -Force -Path $SysmonDir | Out-Null

Write-Host "[1/7] Download Wazuh Agent"
Invoke-WebRequest -Uri $WazuhUrl -OutFile $WazuhMsi

Write-Host "[2/7] Install Wazuh Agent"
Start-Process msiexec.exe -Wait -NoNewWindow -ArgumentList @(
    "/i `"$WazuhMsi`"",
    "/q",
    "WAZUH_MANAGER=`"$WazuhManager`"",
    "WAZUH_AGENT_NAME=`"$AgentName`"",
    "WAZUH_AGENT_GROUP=`"$AgentGroup`""
)

Start-Sleep -Seconds 5

Write-Host "[3/7] Download Sysmon"
Invoke-WebRequest -Uri $SysmonUrl -OutFile $SysmonExe

Write-Host "[4/7] Download Sysmon Config"
Invoke-WebRequest -Uri $ConfigUrl -OutFile $SysmonConfig

Write-Host "[5/7] Install/Update Sysmon"
if (Get-Service Sysmon64 -ErrorAction SilentlyContinue) {
    & $SysmonExe -accepteula -c $SysmonConfig
}
else {
    & $SysmonExe -accepteula -i $SysmonConfig
}

Write-Host "[6/7] Add Sysmon EventChannel to Wazuh Agent"
if (!(Test-Path $WazuhConf)) {
    Write-Host "[ERROR] ไม่พบ $WazuhConf"
    exit 1
}

Copy-Item $WazuhConf "$WazuhConf.bak_$(Get-Date -Format yyyyMMdd_HHmmss)"
$Content = Get-Content $WazuhConf -Raw

if ($Content -notmatch "Microsoft-Windows-Sysmon/Operational") {
    $Block = @"

  <localfile>
    <location>Microsoft-Windows-Sysmon/Operational</location>
    <log_format>eventchannel</log_format>
  </localfile>
"@
    $Content = $Content -replace "</ossec_config>", "$Block`n</ossec_config>"
    Set-Content -Path $WazuhConf -Value $Content -Encoding UTF8
}

Write-Host "[7/7] Restart Wazuh Agent"
Restart-Service WazuhSvc -Force

Write-Host "DONE"
Get-Service WazuhSvc, Sysmon64 | Format-Table -AutoSize