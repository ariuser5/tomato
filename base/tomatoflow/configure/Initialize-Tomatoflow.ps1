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

$flowConfigUtilsModule = Join-Path $PSScriptRoot '.\modules\FlowConfigUtils.psm1'
Import-Module $flowConfigUtilsModule -Force

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

function New-FlowAutomations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Type
    )

    # Flow folders are top-level peers of "tomatoflow-setup" in the automation menu.
    $flowCategory = @($Name)

    $automationsCwd = '$env:TOMATO_ROOT/base/tomatoflow/automations'
    $defaultMailerParamFile = '$TOMATO_ROOT/base/resources/mailer-sample.json'
    $defaultLabelArchiveMapFile = '$TOMATO_ROOT/base/resources/archive-label-map.json'

    return @(
        [pscustomobject]@{
            alias = 'Run Monthly Flow'
            categoryPath = $flowCategory
            command = '& "$env:TOMATO_ROOT/base/tomatoflow/automations/Run-MonthlyFlow.ps1"'
            args = @('-FlowName', $Name, '-StoragePath', $Path, '-PathType', $Type, '-MailerParamFile', $defaultMailerParamFile)
            cwd = $automationsCwd
        },
        [pscustomobject]@{
            alias = 'Preview Storage'
            categoryPath = $flowCategory
            command = '& "$env:TOMATO_ROOT/base/tomatoflow/automations/Run-SingleScript.ps1"'
            args = @(
                '-ScriptPath', '$env:TOMATO_ROOT/base/utils/Preview-Location.ps1',
                '-PRoot', $Path,
                '-PNavigator', 'auto',
                '-PMaxDepth', '0',
                '-PTitle', 'Preview'
            )
            cwd = $automationsCwd
        },
        [pscustomobject]@{
            alias = 'Ensure New Month Folder'
            categoryPath = $flowCategory
            command = '& "$env:TOMATO_ROOT/base/tomatoflow/automations/Run-SingleScript.ps1"'
            args = @(
                '-ScriptPath', 'Ensure-NewMonthFolder.ps1',
                '-PPath', $Path,
                '-PPathType', $Type
            )
            cwd = $automationsCwd
        },
        [pscustomobject]@{
            alias = 'Label Files'
            categoryPath = $flowCategory
            command = '& "$env:TOMATO_ROOT/base/tomatoflow/automations/Run-SingleScript.ps1"'
            args = @(
                '-ScriptPath', 'Label-Files.ps1',
                '-PStoragePath', $Path,
                '-PPathType', $Type,
                '-PPath', '$Prompt'
            )
            cwd = $automationsCwd
        },
        [pscustomobject]@{
            alias = 'Archive By Label'
            categoryPath = $flowCategory
            command = '& "$env:TOMATO_ROOT/base/tomatoflow/automations/Run-SingleScript.ps1"'
            args = @(
                '-ScriptPath', 'Archive-ByLabel.ps1',
                '-PStoragePath', $Path,
                '-PPathType', $Type,
                '-PPath', '$Prompt',
                '-PLabelArchiveMapFile', $defaultLabelArchiveMapFile
            )
            cwd = $automationsCwd
        },
        [pscustomobject]@{
            alias = 'Create Draft Email'
            categoryPath = $flowCategory
            command = '& "$env:TOMATO_ROOT/base/tomatoflow/automations/Run-SingleScript.ps1"'
            args = @(
                '-ScriptPath', 'Create-DraftEmail.ps1',
                '-PStoragePath', $Path,
                '-PPathType', $Type,
                '-PPath', '$Prompt',
                '-PMailerParamFile', $defaultMailerParamFile,
                '-PDefaultAttachmentPatterns', '[Aa]rchives/'
            )
            cwd = $automationsCwd
        },
        [pscustomobject]@{
            alias = 'Conclude Month Folder'
            categoryPath = $flowCategory
            command = '& "$env:TOMATO_ROOT/base/tomatoflow/automations/Run-SingleScript.ps1"'
            args = @(
                '-ScriptPath', 'Conclude-MonthFolder.ps1',
                '-PPath', $Path,
                '-PPathType', $Type,
                '-PTargetFolderName', '$Prompt'
            )
            cwd = $automationsCwd
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
$managedAliases = Get-ManagedFlowAliases

$filtered = @()
foreach ($entry in $existingAutomations) {
    if ($null -eq $entry) { continue }

    $categoryPath = @(Get-CategoryPathSegments -Entry $entry)
    $entryFlowName = if ($categoryPath.Count -gt 0) { $categoryPath[0] } else { '' }
    $alias = if ($entry.PSObject.Properties.Name -contains 'alias') { ([string]$entry.alias).Trim() } else { '' }
    $isManagedFlowEntry = ($entryFlowName -and ($entryFlowName -ne 'tomatoflow-setup') -and ($managedAliases -contains $alias))
    $isSameFlow = ($entryFlowName -eq $resolvedFlowName)

    if ($isManagedFlowEntry -and $isSameFlow) {
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
