#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

$WazuhAgentPath = "C:\Program Files (x86)\ossec-agent"
$ActiveResponseBinPath = Join-Path $WazuhAgentPath "active-response\bin"
$SourceDir = Split-Path -Parent $MyInvocation.MyCommand.Path

$SourceBlockScript = Join-Path $SourceDir "block-malicious.ps1"
$SourceActionScript = Join-Path $SourceDir "action-script.bat"
$DestBlockScript = Join-Path $ActiveResponseBinPath "block-malicious.ps1"
$DestActionScript = Join-Path $ActiveResponseBinPath "action-script.bat"

Write-Host "=============================================="
Write-Host " Wazuh Windows Active Response Setup"
Write-Host "=============================================="
Write-Host ""

if (-not (Test-Path $WazuhAgentPath)) {
    Write-Host "[ERROR] ไม่พบ Wazuh Agent ที่ $WazuhAgentPath"
    exit 1
}

if (-not (Test-Path $SourceBlockScript)) {
    Write-Host "[ERROR] ไม่พบไฟล์ $SourceBlockScript"
    exit 1
}

if (-not (Test-Path $SourceActionScript)) {
    Write-Host "[ERROR] ไม่พบไฟล์ $SourceActionScript"
    exit 1
}

New-Item -ItemType Directory -Path $ActiveResponseBinPath -Force | Out-Null
Write-Host "[1/4] Ready path: $ActiveResponseBinPath"

Copy-Item -Path $SourceBlockScript -Destination $DestBlockScript -Force
Copy-Item -Path $SourceActionScript -Destination $DestActionScript -Force
Write-Host "[2/4] Copied Active Response files"

Unblock-File -Path $DestBlockScript -ErrorAction SilentlyContinue
Unblock-File -Path $DestActionScript -ErrorAction SilentlyContinue
Write-Host "[3/4] Unblocked copied files"

$service = Get-Service -Name "WazuhSvc" -ErrorAction SilentlyContinue
if (-not $service) {
    Write-Host "[ERROR] ไม่พบ service WazuhSvc"
    exit 1
}

Restart-Service -Name "WazuhSvc" -Force
Write-Host "[4/4] Restarted WazuhSvc"

Write-Host ""
Write-Host "DONE"
Write-Host "block script : $DestBlockScript"
Write-Host "action script: $DestActionScript"
Write-Host "service      : WazuhSvc"
