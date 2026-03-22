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
    [string]$ArtifactsSourcePath,

    [Parameter()]
    [string]$MailerParamFile,

    [Parameter()]
    [string]$LabelsFilePath,

    [Parameter()]
    [string]$LabelArchiveMapFile,

    [Parameter()]
    [ValidateSet('Auto', 'Local', 'Remote')]
    [string]$PathType = 'Auto'
)

$ErrorActionPreference = 'Stop'

$resultUtilsModule = Join-Path $PSScriptRoot '..\..\utils\common\ResultUtils.psm1'
Import-Module $resultUtilsModule -Force

$flowConfigUtilsModule = Join-Path $PSScriptRoot '.\modules\FlowConfigUtils.psm1'
Import-Module $flowConfigUtilsModule -Force

$defaultMailerParamFile = '$TOMATO_ROOT/base/resources/mailer-sample.json'
$defaultLabelsFilePath = '$TOMATO_ROOT/base/resources/gdrive-labels.txt'
$defaultLabelArchiveMapFile = '$TOMATO_ROOT/base/resources/archive-label-map.json'

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
        [Parameter(Mandatory = $true)][string]$Type,
        [Parameter()][string]$ArtifactsPath,
        [Parameter(Mandatory = $true)][string]$MailerFilePath,
        [Parameter(Mandatory = $true)][string]$LabelsPath,
        [Parameter(Mandatory = $true)][string]$ArchiveMapFilePath
    )

    # Flow folders are top-level peers of "tomatoflow-setup" in the automation menu.
    $flowCategory = @($Name)

    $automationsCwd = '$env:TOMATO_ROOT/base/tomatoflow/automations'
    $runMonthlyArgs = @(
        '-FlowName', $Name,
        '-StoragePath', $Path,
        '-PathType', $Type,
        '-MailerParamFile', $MailerFilePath,
        '-LabelsFilePath', $LabelsPath,
        '-LabelArchiveMapFile', $ArchiveMapFilePath
    )
    if (([string]$ArtifactsPath ?? '').Trim()) {
        $runMonthlyArgs += @('-ArtifactsSourcePath', $ArtifactsPath)
    }

    return @(
        [pscustomobject]@{
            alias = 'Run Monthly Flow'
            categoryPath = $flowCategory
            command = '& "$env:TOMATO_ROOT/base/tomatoflow/automations/Run-MonthlyFlow.ps1"'
            args = $runMonthlyArgs
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
                '-PPath', '$Prompt',
                '-PLabelsFilePath', $LabelsPath
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
                '-PLabelArchiveMapFile', $ArchiveMapFilePath
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
                '-PMailerParamFile', $MailerFilePath,
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

function Resolve-ConfiguredFilePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RawPath
    )

    $value = ([string]$RawPath ?? '').Trim()
    if (-not $value) {
        return ''
    }

    $tomatoRoot = ([string]$env:TOMATO_ROOT ?? '').Trim()
    $expanded = $value
    if ($tomatoRoot) {
        if ($expanded -like '$env:TOMATO_ROOT/*' -or $expanded -like '$env:TOMATO_ROOT\\*') {
            $suffix = $expanded.Substring('$env:TOMATO_ROOT'.Length).TrimStart('/', [char]'\')
            $expanded = Join-Path $tomatoRoot $suffix
        }
        elseif ($expanded -like '$TOMATO_ROOT/*' -or $expanded -like '$TOMATO_ROOT\\*') {
            $suffix = $expanded.Substring('$TOMATO_ROOT'.Length).TrimStart('/', [char]'\')
            $expanded = Join-Path $tomatoRoot $suffix
        }
        elseif ($expanded -like '%TOMATO_ROOT%/*' -or $expanded -like '%TOMATO_ROOT%\\*') {
            $suffix = $expanded.Substring('%TOMATO_ROOT%'.Length).TrimStart('/', [char]'\')
            $expanded = Join-Path $tomatoRoot $suffix
        }
    }

    if (-not [System.IO.Path]::IsPathRooted($expanded)) {
        $baseDir = if ($tomatoRoot) { $tomatoRoot } else { (Get-Location).Path }
        $expanded = Join-Path $baseDir $expanded
    }

    return [System.IO.Path]::GetFullPath($expanded)
}

function Resolve-ConfigFileInput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PromptLabel,

        [Parameter(Mandatory = $true)]
        [string]$DefaultPath,

        [Parameter()]
        [string]$InitialValue,

        [Parameter()]
        [bool]$HasInitialValue = $false
    )

    $candidate = ([string]$InitialValue ?? '').Trim()

    while ($true) {
        if ($Host.UI -and $Host.UI.RawUI -and (-not $HasInitialValue)) {
            $entered = (Read-Host ("{0} (Enter = default: {1})" -f $PromptLabel, $DefaultPath)).Trim()
            if (-not $entered) {
                return $DefaultPath
            }

            $candidate = $entered
        }
        elseif (-not $candidate) {
            return $DefaultPath
        }

        $resolvedCandidate = Resolve-ConfiguredFilePath -RawPath $candidate
        if (Test-Path -LiteralPath $resolvedCandidate -PathType Leaf) {
            return $candidate
        }

        Write-Host "Configured file not found: $resolvedCandidate" -ForegroundColor Red

        if (-not ($Host.UI -and $Host.UI.RawUI)) {
            throw "Configured file does not exist for '$PromptLabel': $resolvedCandidate"
        }

        $retryChoice = (Read-Host "Retry '$PromptLabel' configuration? [Yes/No] (default: Yes)").Trim().ToLowerInvariant()
        if ($retryChoice -eq 'n' -or $retryChoice -eq 'no') {
            throw "Configuration aborted: invalid file path for '$PromptLabel'."
        }

        $HasInitialValue = $false
        $candidate = ''
    }
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

$resolvedArtifactsSourcePath = ([string]$ArtifactsSourcePath ?? '').Trim()
if (-not $resolvedArtifactsSourcePath -and $Host.UI -and $Host.UI.RawUI) {
    Write-Host "Please provide an optional source path for template artifacts to copy into the new month folder." -ForegroundColor Cyan
    Write-Host "This can be useful for pre-populating the folder with standard files or templates." -ForegroundColor Cyan
    $resolvedArtifactsSourcePath = (Read-Host 'Artifacts source path (optional, leave empty to skip copy)').Trim()
}

$resolvedMailerParamFile = Resolve-ConfigFileInput -PromptLabel 'Mailer param file' -DefaultPath $defaultMailerParamFile -InitialValue $MailerParamFile -HasInitialValue $PSBoundParameters.ContainsKey('MailerParamFile')
$resolvedLabelsFilePath = Resolve-ConfigFileInput -PromptLabel 'Labels input file' -DefaultPath $defaultLabelsFilePath -InitialValue $LabelsFilePath -HasInitialValue $PSBoundParameters.ContainsKey('LabelsFilePath')
$resolvedLabelArchiveMapFile = Resolve-ConfigFileInput -PromptLabel 'Label-to-archive map file' -DefaultPath $defaultLabelArchiveMapFile -InitialValue $LabelArchiveMapFile -HasInitialValue $PSBoundParameters.ContainsKey('LabelArchiveMapFile')

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

$newFlowAutomations = New-FlowAutomations -Name $resolvedFlowName -Path $resolvedStoragePath -Type $PathType -ArtifactsPath $resolvedArtifactsSourcePath -MailerFilePath $resolvedMailerParamFile -LabelsPath $resolvedLabelsFilePath -ArchiveMapFilePath $resolvedLabelArchiveMapFile
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
    ArtifactsSourcePath = $resolvedArtifactsSourcePath
    MailerParamFile = $resolvedMailerParamFile
    LabelsFilePath = $resolvedLabelsFilePath
    LabelArchiveMapFile = $resolvedLabelArchiveMapFile
        PathType = $PathType
        MetadataPath = $metadataFilePath
        AddedAutomations = @($newFlowAutomations | ForEach-Object { $_.alias })
    })

exit 0
