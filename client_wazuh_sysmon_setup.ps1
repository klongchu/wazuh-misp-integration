# Boundary map for refactoring:
# - Windows-specific wrapper: admin check, MSI install/update, Sysmon, ossec.conf edit, active response, service restart
# - Shared/edit-worthy logic: config backup and parse/validate patterns reused by installer steps
#requires -RunAsAdministrator

[CmdletBinding()]
param(
    [Parameter(Position = 0, Mandatory = $false, HelpMessage = "Wazuh Manager IP or Domain (FQDN)")]
    [Alias("Manager", "Server", "Domain", "IP", "WazuhServer")]
    [string]$WazuhManager,

    [Parameter(Position = 1, Mandatory = $false, HelpMessage = "Wazuh Agent Group (default: windows,sysmon,misp)")]
    [Alias("Group", "WazuhGroup")]
    [string]$AgentGroup,

    [Parameter(Position = 2, Mandatory = $false, HelpMessage = "Install Active Response for IP blocking (Y/n)")]
    [Alias("ActiveResponse", "AR")]
    [string]$InstallActiveResponse,

    [Parameter(Mandatory = $false, HelpMessage = "Wazuh Agent Name (default: ComputerName)")]
    [Alias("Name", "WazuhAgentName")]
    [string]$AgentName,

    [Parameter(Mandatory = $false, HelpMessage = "Reinstall mode: reinstall or uninstall (default: reinstall)")]
    [Alias("Mode")]
    [string]$ReinstallMode
)

# Wazuh Agent + Sysmon + Active Response Setup for Windows Clients
#
# Refactor map for later core + wrapper split:
# - Core Logic: prerequisite checks, interactive prompts, download helpers, config backup,
#   managed ossec.conf updates, and service validation/restart flow.
# - Windows Role Logic: MSI-based agent install/reinstall, Sysmon download/install,
#   Windows event channel wiring, and Windows Firewall active response.
#
# ===== Core Logic: shared validation, prompt flow, and helper functions =====
# ===== Windows Role Logic begins below after helper definitions =====

# Check for required commands
if (-not (Get-Command msiexec.exe -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] msiexec.exe not found. Please ensure it is available in your system PATH."
    exit 1
}

# Check for curl equivalent (Invoke-WebRequest)
if (-not (Get-Command Invoke-WebRequest -ErrorAction SilentlyContinue)) {
    Write-Host "[ERROR] Invoke-WebRequest not found. Please ensure PowerShell is updated or provide an alternative download method."
    exit 1
}

$ErrorActionPreference = "Stop"

# Explicit Administrator privilege check
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[ERROR] สคริปต์นี้ต้องรันด้วยสิทธิ์ Administrator (Run as Administrator)"
    exit 1
}

# Ensure TLS 1.2+ is enabled for secure downloads
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

Write-Host "=============================================="
Write-Host " Wazuh Agent + Sysmon + Active Response Setup"
Write-Host "=============================================="
Write-Host ""

# 1. Wazuh Manager IP / Domain
if ([string]::IsNullOrWhiteSpace($WazuhManager)) {
    $WazuhManager = Read-Host "Wazuh Manager IP / Domain (FQDN)"
}

if ([string]::IsNullOrWhiteSpace($WazuhManager)) {
    Write-Host "[ERROR] Wazuh Manager IP / Domain ห้ามว่าง"
    exit 1
}

# 2. Agent Name
if ([string]::IsNullOrWhiteSpace($AgentName)) {
    $AgentNameInput = Read-Host "Agent Name [Enter = $env:COMPUTERNAME]"
    if (-not [string]::IsNullOrWhiteSpace($AgentNameInput)) {
        $AgentName = $AgentNameInput
    } else {
        $AgentName = $env:COMPUTERNAME
    }
}

# 3. Agent Group
if ([string]::IsNullOrWhiteSpace($AgentGroup)) {
    $AgentGroupInput = Read-Host "Agent Group [Enter = windows,sysmon,misp]"
    if (-not [string]::IsNullOrWhiteSpace($AgentGroupInput)) {
        $AgentGroup = $AgentGroupInput
    } else {
        $AgentGroup = "windows,sysmon,misp"
    }
}

# 4. Active Response
if ([string]::IsNullOrWhiteSpace($InstallActiveResponse)) {
    $InstallActiveResponseInput = Read-Host "Install Active Response for IP blocking? [Y/n]"
    if (-not [string]::IsNullOrWhiteSpace($InstallActiveResponseInput)) {
        $InstallActiveResponse = $InstallActiveResponseInput
    } else {
        $InstallActiveResponse = "Y"
    }
}

# 5. Reinstall Mode
if ([string]::IsNullOrWhiteSpace($ReinstallMode)) {
    $ReinstallModeInput = Read-Host "If Wazuh Agent already exists: reinstall in-place or uninstall first? [reinstall/uninstall, default=reinstall]"
    if (-not [string]::IsNullOrWhiteSpace($ReinstallModeInput)) {
        $ReinstallMode = $ReinstallModeInput
    } else {
        $ReinstallMode = "reinstall"
    }
}

Write-Host ""
Write-Host "[CONFIG] Target Manager   : $WazuhManager"
Write-Host "[CONFIG] Agent Name       : $AgentName"
Write-Host "[CONFIG] Agent Group      : $AgentGroup"
Write-Host "[CONFIG] Active Response  : $InstallActiveResponse"
Write-Host "[CONFIG] Reinstall Mode   : $ReinstallMode"
Write-Host ""

$TempDir = "$env:TEMP\wazuh_sysmon"
$WazuhMsi = "$TempDir\wazuh-agent.msi"
$WazuhMsiLog = "$TempDir\wazuh-agent-install.log"
$WazuhAgentPath = "C:\Program Files (x86)\ossec-agent"
if (-not (Test-Path $WazuhAgentPath) -and (Test-Path "C:\Program Files\ossec-agent")) {
    $WazuhAgentPath = "C:\Program Files\ossec-agent"
}
$WazuhConf = Join-Path $WazuhAgentPath "ossec.conf"
$ActiveResponseBinPath = Join-Path $WazuhAgentPath "active-response\bin"
$DestBlockScript = Join-Path $ActiveResponseBinPath "block-malicious.ps1"
$DestActionScript = Join-Path $ActiveResponseBinPath "action-script.bat"

$Is64Bit = [Environment]::Is64BitOperatingSystem
$SysmonExeName = if ($Is64Bit) { "Sysmon64.exe" } else { "Sysmon.exe" }
$SysmonDir = "C:\Program Files\Sysmon"
$SysmonExe = Join-Path $SysmonDir $SysmonExeName
$SysmonConfig = Join-Path $SysmonDir "sysmonconfig.xml"

$FallbackWazuhVersion = "4.14.1"
$WazuhVersion = $FallbackWazuhVersion
$WazuhUrl = "https://packages.wazuh.com/4.x/windows/wazuh-agent-$WazuhVersion-1.msi"
$SysmonUrl = if ($Is64Bit) { "https://live.sysinternals.com/Sysmon64.exe" } else { "https://live.sysinternals.com/Sysmon.exe" }
$SysmonZipUrl = "https://download.sysinternals.com/files/Sysmon.zip"
$ConfigUrl = "https://raw.githubusercontent.com/SwiftOnSecurity/sysmon-config/master/sysmonconfig-export.xml"

function Invoke-WebDownload {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$OutFile
    )

    Invoke-WebRequest -UseBasicParsing -Uri $Uri -OutFile $OutFile
}

function Test-WebFileExists {
    param([Parameter(Mandatory = $true)][string]$Uri)

    try {
        Invoke-WebRequest -UseBasicParsing -Method Head -Uri $Uri -TimeoutSec 20 | Out-Null
        return $true
    }
    catch {
        return $false
    }
}

function Get-LatestWazuhVersion {
    try {
        $Release = Invoke-RestMethod -Uri "https://api.github.com/repos/wazuh/wazuh/releases/latest" -TimeoutSec 20
        $Version = ([string]$Release.tag_name).TrimStart('v')

        if ($Version -match '^\d+\.\d+\.\d+$') {
            return $Version
        }
    }
    catch {
        Write-Host "[WARNING] Cannot check latest Wazuh version: $($_.Exception.Message)"
    }

    return $null
}

New-Item -ItemType Directory -Force -Path $TempDir | Out-Null
New-Item -ItemType Directory -Force -Path $SysmonDir | Out-Null

Write-Host "[1/10] Check latest Wazuh Agent version"
$LatestWazuhVersion = Get-LatestWazuhVersion
if (-not [string]::IsNullOrWhiteSpace($LatestWazuhVersion)) {
    $CandidateWazuhUrl = "https://packages.wazuh.com/4.x/windows/wazuh-agent-$LatestWazuhVersion-1.msi"

    if (Test-WebFileExists -Uri $CandidateWazuhUrl) {
        $WazuhVersion = $LatestWazuhVersion
        $WazuhUrl = $CandidateWazuhUrl
    }
    else {
        Write-Host "[WARNING] Latest Wazuh MSI not found: $CandidateWazuhUrl"
        Write-Host "[WARNING] Fallback to Wazuh Agent $FallbackWazuhVersion"
    }
}
else {
    Write-Host "[WARNING] Fallback to Wazuh Agent $FallbackWazuhVersion"
}

Write-Host "[INFO] Wazuh Agent version: $WazuhVersion"
Write-Host "[INFO] Wazuh Agent URL: $WazuhUrl"

Write-Host "[1/10] Download Wazuh Agent"
Invoke-WebDownload -Uri $WazuhUrl -OutFile $WazuhMsi

$ExistingWazuhService = Get-Service -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '^WazuhSvc$' -or $_.Name -match '^wazuh-agent$' -or $_.Name -match '^ossec-agent$' -or $_.DisplayName -match '^Wazuh Agent$'
} | Select-Object -First 1

if ($null -ne $ExistingWazuhService) {
    Write-Host "[INFO] Existing Wazuh Agent detected: $($ExistingWazuhService.Name) / $($ExistingWazuhService.DisplayName)"

    if ($ReinstallMode -match '^(uninstall|remove)$') {
        Write-Host "[2/10] Uninstall old Wazuh Agent"
        if ($ExistingWazuhService.Status -eq 'Running') {
            Stop-Service -Name $ExistingWazuhService.Name -Force -ErrorAction SilentlyContinue
        }

        $UninstallProcess = Start-Process msiexec.exe -Wait -NoNewWindow -PassThru -ArgumentList @(
            "/x `"$WazuhMsi`"",
            "/qn",
            "/L*v `"$WazuhMsiLog`""
        )

        if ($UninstallProcess.ExitCode -ne 0 -and $UninstallProcess.ExitCode -ne 3010) {
            Write-Host "[ERROR] Wazuh Agent uninstall failed. ExitCode: $($UninstallProcess.ExitCode)"
            Write-Host "MSI log: $WazuhMsiLog"
            exit 1
        }

        Start-Sleep -Seconds 10
    }
    else {
        Write-Host "[2/10] Existing Wazuh Agent found. Continue with reinstall in-place"
    }
}
else {
    Write-Host "[2/10] No existing Wazuh Agent found. Continue with fresh install"
}

Write-Host "[3/10] Install/Update Wazuh Agent"
$MsiProcess = Start-Process msiexec.exe -Wait -NoNewWindow -PassThru -ArgumentList @(
    "/i `"$WazuhMsi`"",
    "/qn",
    "/L*v `"$WazuhMsiLog`"",
    "WAZUH_MANAGER=`"$WazuhManager`"",
    "WAZUH_AGENT_NAME=`"$AgentName`"",
    "WAZUH_AGENT_GROUP=`"$AgentGroup`""
)

if ($MsiProcess.ExitCode -ne 0 -and $MsiProcess.ExitCode -ne 3010) {
    Write-Host "[ERROR] Wazuh Agent MSI install failed. ExitCode: $($MsiProcess.ExitCode)"
    Write-Host "MSI log: $WazuhMsiLog"
    exit 1
}

if ($MsiProcess.ExitCode -eq 3010) {
    Write-Host "[WARNING] Wazuh Agent MSI requested reboot. Continue, but reboot may be required."
}

Start-Sleep -Seconds 10

Write-Host "[4/10] Download Sysmon"
$SysmonDownloaded = $false
try {
    Invoke-WebDownload -Uri $SysmonUrl -OutFile $SysmonExe
    if ((Test-Path $SysmonExe) -and ((Get-Item $SysmonExe).Length -gt 100000)) {
        $SysmonDownloaded = $true
        Write-Host "[OK] Downloaded $SysmonExeName directly."
    }
}
catch {
    Write-Host "[WARNING] Direct Sysmon download failed: $($_.Exception.Message)"
}

if (-not $SysmonDownloaded) {
    Write-Host "[INFO] Attempting download from Sysmon.zip fallback..."
    $SysmonZip = "$TempDir\Sysmon.zip"
    try {
        Invoke-WebDownload -Uri $SysmonZipUrl -OutFile $SysmonZip
        if (Test-Path $SysmonZip) {
            Expand-Archive -Path $SysmonZip -DestinationPath $TempDir -Force
            $ExtractedExe = Join-Path $TempDir $SysmonExeName
            if (Test-Path $ExtractedExe) {
                Copy-Item -Path $ExtractedExe -Destination $SysmonExe -Force
                $SysmonDownloaded = $true
                Write-Host "[OK] Extracted $SysmonExeName from Sysmon.zip."
            }
        }
    }
    catch {
        Write-Host "[WARNING] Sysmon.zip download/extract failed: $($_.Exception.Message)"
    }
}

if (-not $SysmonDownloaded -or -not (Test-Path $SysmonExe)) {
    $WindowsSysmonExe = "C:\Windows\$SysmonExeName"
    if (Test-Path $WindowsSysmonExe) {
        Write-Host "[INFO] Found existing Sysmon binary at $WindowsSysmonExe"
        Copy-Item -Path $WindowsSysmonExe -Destination $SysmonExe -Force
        $SysmonDownloaded = $true
    }
}

if (-not (Test-Path $SysmonExe) -or ((Get-Item $SysmonExe).Length -lt 100000)) {
    Write-Host "[ERROR] Failed to download or locate a valid Sysmon executable."
    exit 1
}

Write-Host "[5/10] Download Sysmon Config"
$ConfigDownloaded = $false
try {
    Invoke-WebDownload -Uri $ConfigUrl -OutFile $SysmonConfig
    if ((Test-Path $SysmonConfig) -and ((Get-Item $SysmonConfig).Length -gt 1000)) {
        $ConfigDownloaded = $true
        Write-Host "[OK] Sysmon configuration downloaded successfully."
    }
}
catch {
    Write-Host "[WARNING] Cannot download Sysmon config from GitHub: $($_.Exception.Message)"
}

if (-not $ConfigDownloaded) {
    if ((Test-Path $SysmonConfig) -and ((Get-Item $SysmonConfig).Length -gt 1000)) {
        Write-Host "[INFO] Reusing existing local Sysmon config: $SysmonConfig"
    }
    else {
        Write-Host "[WARNING] Sysmon config XML unavailable. Sysmon will be installed with default configuration."
    }
}

Write-Host "[6/10] Install/Update Sysmon"
$HasValidConfig = (Test-Path $SysmonConfig) -and ((Get-Item $SysmonConfig).Length -gt 1000)

$ExistingSysmon = Get-Service -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match '^Sysmon(64)?$' -or $_.DisplayName -match '^Sysmon'
} | Select-Object -First 1

if ($null -ne $ExistingSysmon) {
    Write-Host "[INFO] Existing Sysmon service found: $($ExistingSysmon.Name) (Status: $($ExistingSysmon.Status))"
    Write-Host "[INFO] Updating Sysmon configuration..."
    $SysmonArgs = @("-accepteula", "-c")
    if ($HasValidConfig) {
        $SysmonArgs += "`"$SysmonConfig`""
    }
    $SysmonProc = Start-Process -FilePath $SysmonExe -ArgumentList $SysmonArgs -Wait -NoNewWindow -PassThru
    if ($SysmonProc.ExitCode -ne 0) {
        Write-Host "[WARNING] Sysmon config update returned exit code $($SysmonProc.ExitCode). Retrying without config file..."
        Start-Process -FilePath $SysmonExe -ArgumentList @("-accepteula", "-c") -Wait -NoNewWindow -PassThru | Out-Null
    }
}
else {
    Write-Host "[INFO] Installing Sysmon service and driver..."
    $SysmonArgs = @("-accepteula", "-i")
    if ($HasValidConfig) {
        $SysmonArgs += "`"$SysmonConfig`""
    }
    $SysmonProc = Start-Process -FilePath $SysmonExe -ArgumentList $SysmonArgs -Wait -NoNewWindow -PassThru
    if ($SysmonProc.ExitCode -ne 0 -and $HasValidConfig) {
        Write-Host "[WARNING] Sysmon install with config failed (ExitCode $($SysmonProc.ExitCode)). Retrying with default configuration..."
        $SysmonProc = Start-Process -FilePath $SysmonExe -ArgumentList @("-accepteula", "-i") -Wait -NoNewWindow -PassThru
    }
    if ($SysmonProc.ExitCode -ne 0) {
        Write-Host "[WARNING] Sysmon installer finished with ExitCode $($SysmonProc.ExitCode)"
    }
}

# Wait for Sysmon service and ensure it is running
$SysmonService = $null
for ($i = 1; $i -le 10; $i++) {
    $SysmonService = Get-Service -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match '^Sysmon(64)?$' -or $_.DisplayName -match '^Sysmon'
    } | Select-Object -First 1
    if ($null -ne $SysmonService) { break }
    Start-Sleep -Seconds 2
}

if ($null -eq $SysmonService) {
    Write-Host "[ERROR] Sysmon service not found after install/update attempt."
    Write-Host "[INFO] Try running manually: & `"$SysmonExe`" -accepteula -i"
}
else {
    Write-Host ("[INFO] Found Sysmon Service: {0} / Status: {1}" -f $SysmonService.Name, $SysmonService.Status)
    if ($SysmonService.Status -ne 'Running') {
        Write-Host "[INFO] Starting Sysmon service ($($SysmonService.Name))..."
        Start-Service -Name $SysmonService.Name -ErrorAction SilentlyContinue
        Start-Sleep -Seconds 3
        $SysmonService = Get-Service -Name $SysmonService.Name -ErrorAction SilentlyContinue
    }

    if ($SysmonService.Status -eq 'Running') {
        Write-Host "[OK] Sysmon service is running."
    }
    else {
        Write-Host "[WARNING] Sysmon service status is $($SysmonService.Status). Try starting manually: Start-Service $($SysmonService.Name)"
    }
}

$SysmonDriver = Get-Service -Name SysmonDrv -ErrorAction SilentlyContinue
if ($null -ne $SysmonDriver) {
    if ($SysmonDriver.Status -eq 'Running') {
        Write-Host "[OK] Sysmon filter driver (SysmonDrv) is running."
    }
    else {
        Write-Host "[WARNING] SysmonDrv driver status: $($SysmonDriver.Status)"
    }
}

Write-Host "[7/10] Configure Sysmon EventChannel and Wazuh Agent"
try {
    wevtutil.exe sl "Microsoft-Windows-Sysmon/Operational" /e:true 2>$null
    Write-Host "[OK] Microsoft-Windows-Sysmon/Operational channel enabled."
}
catch {
    Write-Host "[WARNING] Could not enable Sysmon event channel via wevtutil: $($_.Exception.Message)"
}

if (!(Test-Path $WazuhConf)) {
    if (Test-Path "$WazuhAgentPath\ossec.conf.save") {
        Copy-Item "$WazuhAgentPath\ossec.conf.save" $WazuhConf -Force
        Write-Host "[INFO] Restored ossec.conf from $WazuhAgentPath\ossec.conf.save"
    }
    elseif (Test-Path "$WazuhAgentPath\last-ossec.conf") {
        Copy-Item "$WazuhAgentPath\last-ossec.conf" $WazuhConf -Force
        Write-Host "[INFO] Restored ossec.conf from $WazuhAgentPath\last-ossec.conf"
    }
    else {
        Write-Host "[ERROR] ไม่พบ $WazuhConf"
        exit 1
    }
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
    $LastIndex = $Content.LastIndexOf("</ossec_config>")
    if ($LastIndex -ge 0) {
        $Content = $Content.Substring(0, $LastIndex) + $Block + "`n" + $Content.Substring($LastIndex)
        Set-Content -Path $WazuhConf -Value $Content -Encoding UTF8
        Write-Host "[OK] Added Sysmon eventchannel to ossec.conf"
    }
    else {
        Write-Host "[WARNING] Could not find </ossec_config> in $WazuhConf"
    }
}
else {
    Write-Host "[INFO] Sysmon EventChannel already present in ossec.conf"
}

if ($InstallActiveResponse -match '^[Yy]$') {
    Write-Host "[8/10] Install Active Response files"
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
    Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    Get-NetFirewallRule -DisplayName "$RuleName Inbound" -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    Write-ArLog "Unblocked MISP IOC IP: $Ioc"
    exit 0
}

$existingRule = Get-NetFirewallRule -DisplayName $RuleName -ErrorAction SilentlyContinue
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

    $ActionScriptContent | Out-File -FilePath $DestActionScript -Force -Encoding ASCII
    $BlockScriptContent | Out-File -FilePath $DestBlockScript -Force -Encoding UTF8
}
else {
    Write-Host "[8/10] Skip Active Response files"
}

Write-Host "[9/10] Restart Wazuh Agent"

$WazuhService = $null
for ($i = 1; $i -le 12; $i++) {
    $WazuhService = Get-Service -Name WazuhSvc -ErrorAction SilentlyContinue
    if ($null -eq $WazuhService) {
        $WazuhService = Get-Service -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^wazuh-agent$' -or $_.Name -match '^ossec-agent$' -or $_.DisplayName -match '^Wazuh Agent$' } | Select-Object -First 1
    }

    if ($null -ne $WazuhService) {
        break
    }

    Write-Host "[INFO] Waiting for Wazuh Agent service... ($i/12)"
    Start-Sleep -Seconds 5
}

if ($null -eq $WazuhService) {
    Write-Host "[ERROR] Wazuh Agent Service not found."
    Write-Host "MSI log: $WazuhMsiLog"
    Write-Host "Run this command to check:"
    Write-Host "Get-Service | Where-Object { `$_.Name -match '^WazuhSvc$|^wazuh-agent$|^ossec-agent$' -or `$_.DisplayName -match '^Wazuh Agent$' }"
    exit 1
}

Write-Host ("[OK] Found Wazuh Service: {0} / {1} / Status: {2}" -f $WazuhService.Name, $WazuhService.DisplayName, $WazuhService.Status)

try {
    if ($WazuhService.Status -eq 'Running') {
        Restart-Service -Name $WazuhService.Name -Force -ErrorAction Stop
    }
    else {
        Start-Service -Name $WazuhService.Name -ErrorAction Stop
    }
}
catch {
    Write-Host "[ERROR] Cannot start Wazuh service: $($WazuhService.Name)"
    Write-Host "[ERROR] Message: $($_.Exception.Message)"
    Write-Host "[INFO] Check Wazuh log: C:\Program Files (x86)\ossec-agent\ossec.log"
    Write-Host "[INFO] Check MSI log: $WazuhMsiLog"
    Write-Host "[INFO] Try start manually: Start-Service WazuhSvc"
    exit 1
}

Start-Sleep -Seconds 10
$WazuhService = Get-Service -Name $WazuhService.Name -ErrorAction SilentlyContinue
if ($null -eq $WazuhService -or $WazuhService.Status -ne 'Running') {
    Write-Host "[ERROR] Wazuh service still not running after start attempt: $($WazuhService.Name)"
    Write-Host "[INFO] Check Wazuh log: C:\Program Files (x86)\ossec-agent\ossec.log"
    Write-Host "[INFO] Check MSI log: $WazuhMsiLog"
    Write-Host "[INFO] Try start manually: Start-Service WazuhSvc"
    exit 1
}

Write-Host "[10/10] Verify services"
$ServicesToVerify = Get-Service -ErrorAction SilentlyContinue | Where-Object {
    ($_.Name -match '^WazuhSvc$' -or $_.Name -match '^wazuh-agent$' -or $_.Name -match '^ossec-agent$' -or $_.DisplayName -match '^Wazuh Agent$') -or
    ($_.Name -match '^Sysmon(64)?$' -or $_.DisplayName -match '^Sysmon') -or
    ($_.Name -match '^SysmonDrv$')
}
$ServicesToVerify | Format-Table Name, DisplayName, Status -AutoSize

$WazuhRunning = $ServicesToVerify | Where-Object { ($_.Name -match '^WazuhSvc$' -or $_.Name -match '^wazuh-agent$' -or $_.DisplayName -match '^Wazuh Agent$') -and $_.Status -eq 'Running' }
$SysmonRunning = $ServicesToVerify | Where-Object { ($_.Name -match '^Sysmon(64)?$' -or $_.DisplayName -match '^Sysmon') -and $_.Status -eq 'Running' }

if ($null -ne $WazuhRunning -and $null -ne $SysmonRunning) {
    Write-Host "[OK] All core services (Wazuh Agent + Sysmon) are running!"
} else {
    if ($null -eq $WazuhRunning) { Write-Host "[WARNING] Wazuh Agent service is not in Running state." }
    if ($null -eq $SysmonRunning) { Write-Host "[WARNING] Sysmon service is not in Running state." }
}

Write-Host "[DONE] Installation completed"
Write-Host ""
Write-Host "Wazuh MSI log         : $WazuhMsiLog"
Write-Host "Wazuh config          : $WazuhConf"
Write-Host "Sysmon config         : $SysmonConfig"
if ($InstallActiveResponse -match '^[Yy]$') {
    Write-Host "Active Response BAT   : $DestActionScript"
    Write-Host "Active Response PS1   : $DestBlockScript"
    Write-Host "Active Response log   : C:\Program Files (x86)\ossec-agent\active-response\active-response.log"
}
Write-Host ""
Write-Host "DONE"