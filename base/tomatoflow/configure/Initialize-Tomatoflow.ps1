# -----------------------------------------------------------------------------
# Initialize-Tomatoflow.ps1
# -----------------------------------------------------------------------------
# Creates or updates local tomatoflow metadata at:
#   %LOCALAPPDATA%/tomato/tomatoflow-meta.json
#
# One configured flow provisions a set of runnable command entries under:
#   ["<FlowName>"]
# -----------------------------------------------------------------------------
[CmdletBinding()]
param(
    [Parameter()]
    [string]$FlowName,

    [Parameter()]
    [string]$StoragePath,

    [Parameter()]
    [ValidateSet('Auto', 'Local', 'Remote')]
    [string]$PathType = 'Auto'
)

$ErrorActionPreference = 'Stop'

$resultUtilsModule = Join-Path $PSScriptRoot '..\..\utils\common\ResultUtils.psm1'
Import-Module $resultUtilsModule -Force

function Get-MetadataFilePath {
    [CmdletBinding()]
    param()

    $localAppData = ([string]$env:LOCALAPPDATA ?? '').Trim()
    if (-not $localAppData) {
        throw 'LOCALAPPDATA is not set. Cannot resolve local metadata file path.'
    }

    $metadataDir = Join-Path $localAppData 'tomato'
    if (-not (Test-Path -LiteralPath $metadataDir -PathType Container)) {
        New-Item -ItemType Directory -Path $metadataDir -Force | Out-Null
    }

    return (Join-Path $metadataDir 'tomatoflow-meta.json')
}

function Read-MetadataConfig {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [pscustomobject]@{ automations = @() }
    }

    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if (-not $raw -or -not $raw.Trim()) {
        return [pscustomobject]@{ automations = @() }
    }

    $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
    if ($parsed -is [array]) {
        return [pscustomobject]@{ automations = @($parsed) }
    }

    if (-not ($parsed.PSObject.Properties.Name -contains 'automations')) {
        return [pscustomobject]@{ automations = @() }
    }

    return [pscustomobject]@{ automations = @($parsed.automations) }
}

function Escape-SingleQuotedValue {
    param([Parameter(Mandatory = $true)][string]$Value)

    return $Value.Replace("'", "''")
}

function New-FlowAutomations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Type
    )

    $escapedName = Escape-SingleQuotedValue -Value $Name
    $escapedPath = Escape-SingleQuotedValue -Value $Path

    # Flow folders are top-level peers of "tomatoflow-setup" in the automation menu.
    $flowCategory = @($Name)

    $runFlowCommand = "& `"$env:BASE_DIR/tomatoflow/automations/Run-MonthlyFlow.ps1`" -FlowName '$escapedName' -Path '$escapedPath' -PathType '$Type'"
    $previewCommand = "& `"$env:BASE_DIR/tomatoflow/automations/Preview-Location.ps1`" -Root '$escapedPath'"
    $ensureCommand = "& `"$env:BASE_DIR/tomatoflow/organization/Ensure-NewMonthFolder.ps1`" -Path '$escapedPath' -PathType '$Type'"

    return @(
        [pscustomobject]@{
            alias = 'Run Monthly Flow'
            categoryPath = $flowCategory
            command = $runFlowCommand
            managedBy = 'tomatoflow-configure'
            flowName = $Name
            storagePath = $Path
            pathType = $Type
        },
        [pscustomobject]@{
            alias = 'Preview Storage'
            categoryPath = $flowCategory
            command = $previewCommand
            managedBy = 'tomatoflow-configure'
            flowName = $Name
            storagePath = $Path
            pathType = $Type
        },
        [pscustomobject]@{
            alias = 'Ensure New Month Folder'
            categoryPath = $flowCategory
            command = $ensureCommand
            managedBy = 'tomatoflow-configure'
            flowName = $Name
            storagePath = $Path
            pathType = $Type
        }
    )
}

$resolvedFlowName = ([string]$FlowName ?? '').Trim()
if (-not $resolvedFlowName -and $Host.UI -and $Host.UI.RawUI) {
    $resolvedFlowName = (Read-Host 'Flow name (for example contractor/party name)').Trim()
}
if (-not $resolvedFlowName) {
    throw 'Flow name is required.'
}

$resolvedStoragePath = ([string]$StoragePath ?? '').Trim()
if (-not $resolvedStoragePath -and $Host.UI -and $Host.UI.RawUI) {
    $resolvedStoragePath = (Read-Host 'Storage path for this flow').Trim()
}
if (-not $resolvedStoragePath) {
    throw 'Storage path is required.'
}

$metadataFilePath = Get-MetadataFilePath
$metadataConfig = Read-MetadataConfig -Path $metadataFilePath
$existingAutomations = @($metadataConfig.automations)

$filtered = @()
foreach ($entry in $existingAutomations) {
    if ($null -eq $entry) { continue }

    $isManaged = (
        (($entry.PSObject.Properties.Name -contains 'managedBy') -and (("$($entry.managedBy)" -eq 'tomatoflow-configure') -or ("$($entry.managedBy)" -eq 'tomatoflow-setup'))) -or
        (($entry.PSObject.Properties.Name -contains 'generatedBy') -and ("$($entry.generatedBy)" -eq 'tomatoflow-setup'))
    )
    $isSameFlow = ($entry.PSObject.Properties.Name -contains 'flowName') -and ("$($entry.flowName)" -eq $resolvedFlowName)

    if ($isManaged -and $isSameFlow) {
        continue
    }

    $filtered += $entry
}

$newFlowAutomations = New-FlowAutomations -Name $resolvedFlowName -Path $resolvedStoragePath -Type $PathType
$merged = @($filtered + $newFlowAutomations)

$payload = [ordered]@{
    automations = $merged
}

$json = $payload | ConvertTo-Json -Depth 12
Set-Content -LiteralPath $metadataFilePath -Value $json -Encoding UTF8

Write-Host "✓ Flow '$resolvedFlowName' configured." -ForegroundColor Green
Write-Host "Metadata file: $metadataFilePath" -ForegroundColor Gray
Write-Host 'Restart Start-Main.ps1 menu (or re-open Automations) to see new entries.' -ForegroundColor Gray

Write-Output (New-ToolResult -Status 'Configured' -Data @{
        FlowName = $resolvedFlowName
        StoragePath = $resolvedStoragePath
        PathType = $PathType
        MetadataPath = $metadataFilePath
        AddedAutomations = @($newFlowAutomations | ForEach-Object { $_.alias })
    })

exit 0
