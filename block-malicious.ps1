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
