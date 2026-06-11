#requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

Write-Host "=============================================="
Write-Host " Wazuh Agent + Sysmon + Active Response Setup"
Write-Host "=============================================="
Write-Host ""

$WazuhManager = Read-Host "Wazuh Manager IP/FQDN"
$AgentName = Read-Host "Agent Name [Enter = ComputerName]"
$AgentGroup = Read-Host "Agent Group [Enter = windows,sysmon,misp]"
$InstallActiveResponse = Read-Host "Install Active Response for IP blocking? [Y/n]"

if ([string]::IsNullOrWhiteSpace($AgentName)) {
    $AgentName = $env:COMPUTERNAME
}

if ([string]::IsNullOrWhiteSpace($AgentGroup)) {
    $AgentGroup = "windows,sysmon,misp"
}

if ([string]::IsNullOrWhiteSpace($InstallActiveResponse)) {
    $InstallActiveResponse = "Y"
}

if ([string]::IsNullOrWhiteSpace($WazuhManager)) {
    Write-Host "[ERROR] Wazuh Manager ห้ามว่าง"
    exit 1
}

$TempDir = "$env:TEMP\wazuh_sysmon"
$WazuhMsi = "$TempDir\wazuh-agent.msi"
$WazuhAgentPath = "C:\Program Files (x86)\ossec-agent"
$WazuhConf = Join-Path $WazuhAgentPath "ossec.conf"
$ActiveResponseBinPath = Join-Path $WazuhAgentPath "active-response\bin"
$DestBlockScript = Join-Path $ActiveResponseBinPath "block-malicious.ps1"
$DestActionScript = Join-Path $ActiveResponseBinPath "action-script.bat"

$SysmonDir = "C:\Program Files\Sysmon"
$SysmonExe = "$SysmonDir\Sysmon64.exe"
$SysmonConfig = "$SysmonDir\sysmonconfig.xml"

$WazuhUrl = "https://packages.wazuh.com/4.x/windows/wazuh-agent-4.14.0-1.msi"
$SysmonUrl = "https://live.sysinternals.com/Sysmon64.exe"
$ConfigUrl = "https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml"

New-Item -ItemType Directory -Force -Path $TempDir | Out-Null
New-Item -ItemType Directory -Force -Path $SysmonDir | Out-Null

Write-Host "[1/10] Download Wazuh Agent"
Invoke-WebRequest -Uri $WazuhUrl -OutFile $WazuhMsi

Write-Host "[2/10] Install/Update Wazuh Agent"
Start-Process msiexec.exe -Wait -NoNewWindow -ArgumentList @(
    "/i `"$WazuhMsi`"",
    "/q",
    "WAZUH_MANAGER=`"$WazuhManager`"",
    "WAZUH_AGENT_NAME=`"$AgentName`"",
    "WAZUH_AGENT_GROUP=`"$AgentGroup`""
)

Start-Sleep -Seconds 5

Write-Host "[3/10] Download Sysmon"
Invoke-WebRequest -Uri $SysmonUrl -OutFile $SysmonExe

Write-Host "[4/10] Download Sysmon Config"
Invoke-WebRequest -Uri $ConfigUrl -OutFile $SysmonConfig

Write-Host "[5/10] Install/Update Sysmon"
if (Get-Service Sysmon64 -ErrorAction SilentlyContinue) {
    & $SysmonExe -accepteula -c $SysmonConfig
}
else {
    & $SysmonExe -accepteula -i $SysmonConfig
}

Write-Host "[6/10] Add Sysmon EventChannel to Wazuh Agent"
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

if ($InstallActiveResponse -match '^[Yy]$') {
    Write-Host "[7/10] Install Active Response files"
    New-Item -ItemType Directory -Path $ActiveResponseBinPath -Force | Out-Null

    $ActionScriptContent = @'
@echo off
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "C:\Program Files (x86)\ossec-agent\active-response\bin\block-malicious.ps1"
'@

    $BlockScriptContent = @'
$ErrorActionPreference = "SilentlyContinue"

$InputJson = [Console]::In.ReadToEnd()
$LogPath = "C:\Program Files (x86)\ossec-agent\active-response\active-response.log"
$RuleGroupPrefix = "Wazuh MISP Block"

function Write-ArLog {
    param([string]$Message)
    Add-Content -Path $LogPath -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $Message"
}

function Get-IocFromAlert {
    param([string]$RawJson)

    try {
        $json = $RawJson | ConvertFrom-Json
    } catch {
        Write-ArLog "Cannot parse Active Response JSON"
        return $null
    }

    $candidates = @(
        $json.parameters.alert.data.misp.value,
        $json.parameters.alert.data.value,
        $json.alert.data.misp.value,
        $json.alert.data.value,
        $json.data.misp.value,
        $json.data.value
    )

    foreach ($candidate in $candidates) {
        if (-not [string]::IsNullOrWhiteSpace($candidate)) {
            return [string]$candidate
        }
    }

    Write-ArLog "IOC value not found in alert JSON"
    return $null
}

function Test-IPv4 {
    param([string]$Value)

    if ($Value -notmatch '^(\d{1,3}\.){3}\d{1,3}$') {
        return $false
    }

    foreach ($octet in $Value.Split('.')) {
        if ([int]$octet -lt 0 -or [int]$octet -gt 255) {
            return $false
        }
    }

    return $true
}

$Action = "add"
try {
    $jsonForAction = $InputJson | ConvertFrom-Json
    if (-not [string]::IsNullOrWhiteSpace($jsonForAction.command)) {
        $Action = [string]$jsonForAction.command
    }
} catch {}

$Ioc = Get-IocFromAlert -RawJson $InputJson
if (-not $Ioc) {
    exit 0
}

if (-not (Test-IPv4 -Value $Ioc)) {
    Write-ArLog "Skip non-IP IOC: $Ioc"
    exit 0
}

$RuleName = "$RuleGroupPrefix $Ioc"

if ($Action -eq "delete") {
    Get-NetFirewallRule -DisplayName $RuleName | Remove-NetFirewallRule
    Get-NetFirewallRule -DisplayName "$RuleName Inbound" | Remove-NetFirewallRule
    Write-ArLog "Unblocked MISP IOC IP: $Ioc"
    exit 0
}

$existingRule = Get-NetFirewallRule -DisplayName $RuleName
if (-not $existingRule) {
    New-NetFirewallRule `
        -DisplayName $RuleName `
        -Direction Outbound `
        -RemoteAddress $Ioc `
        -Action Block `
        -Profile Any `
        -Enabled True | Out-Null

    New-NetFirewallRule `
        -DisplayName "$RuleName Inbound" `
        -Direction Inbound `
        -RemoteAddress $Ioc `
        -Action Block `
        -Profile Any `
        -Enabled True | Out-Null

    Write-ArLog "Blocked MISP IOC IP: $Ioc"
} else {
    Write-ArLog "MISP IOC IP already blocked: $Ioc"
}

exit 0
'@

    Set-Content -Path $DestActionScript -Value $ActionScriptContent -Encoding ASCII
    Set-Content -Path $DestBlockScript -Value $BlockScriptContent -Encoding UTF8
    Unblock-File -Path $DestActionScript -ErrorAction SilentlyContinue
    Unblock-File -Path $DestBlockScript -ErrorAction SilentlyContinue
}
else {
    Write-Host "[7/10] Skip Active Response files"
}

Write-Host "[8/10] Restart Wazuh Agent"

$WazuhService = Get-Service -ErrorAction SilentlyContinue |
Where-Object {
    ($_.Name -match 'wazuh|ossec') -or
    ($_.DisplayName -match 'wazuh|ossec')
} |
Select-Object -First 1

if ($null -eq $WazuhService) {
    Write-Host "[ERROR] Not found Wazuh Agent Service"
    Write-Host "Run this command to check:"
    Write-Host "Get-Service | Where-Object { `$_.Name -match 'wazuh|ossec' -or `$_.DisplayName -match 'wazuh|ossec' }"
    exit 1
}

Write-Host ("[OK] Found Wazuh Service: {0} / {1}" -f $WazuhService.Name, $WazuhService.DisplayName)

if ($WazuhService.Status -eq 'Running') {
    Restart-Service -Name $WazuhService.Name -Force
}
else {
    Start-Service -Name $WazuhService.Name
}

Write-Host "[9/10] Verify services"
Get-Service -ErrorAction SilentlyContinue |
Where-Object {
    ($_.Name -match 'wazuh|ossec|Sysmon64') -or
    ($_.DisplayName -match 'wazuh|ossec|Sysmon')
} |
Format-Table Name, DisplayName, Status -AutoSize

Write-Host "[10/10] Done"
Write-Host ""
Write-Host "Wazuh config          : $WazuhConf"
Write-Host "Sysmon config         : $SysmonConfig"
if ($InstallActiveResponse -match '^[Yy]$') {
    Write-Host "Active Response BAT   : $DestActionScript"
    Write-Host "Active Response PS1   : $DestBlockScript"
    Write-Host "Active Response log   : C:\Program Files (x86)\ossec-agent\active-response\active-response.log"
}
Write-Host ""
Write-Host "DONE"