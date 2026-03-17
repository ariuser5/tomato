# -----------------------------------------------------------------------------
# List-Tomatoflows.ps1
# -----------------------------------------------------------------------------
# Lists configured flows from local tomatoflow metadata.
# -----------------------------------------------------------------------------
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$resultUtilsModule = Join-Path $PSScriptRoot '..\..\utils\common\ResultUtils.psm1'
Import-Module $resultUtilsModule -Force

$localAppData = ([string]$env:LOCALAPPDATA ?? '').Trim()
if (-not $localAppData) {
    throw 'LOCALAPPDATA is not set.'
}

$metadataFilePath = Join-Path (Join-Path $localAppData 'tomato') 'tomatoflow-meta.json'
if (-not (Test-Path -LiteralPath $metadataFilePath -PathType Leaf)) {
    Write-Host 'No configured tomatoflows found yet.' -ForegroundColor Yellow
    Write-Output (New-ToolResult -Status 'Empty' -Data @{
            MetadataPath = $metadataFilePath
            FlowCount = 0
            Flows = @()
        })
    exit 0
}

$raw = Get-Content -LiteralPath $metadataFilePath -Raw -Encoding UTF8
if (-not $raw -or -not $raw.Trim()) {
    Write-Host 'No configured tomatoflows found yet.' -ForegroundColor Yellow
    Write-Output (New-ToolResult -Status 'Empty' -Data @{
            MetadataPath = $metadataFilePath
            FlowCount = 0
            Flows = @()
        })
    exit 0
}

$parsed = $raw | ConvertFrom-Json -ErrorAction Stop
$entries = @()
if ($parsed -is [array]) {
    $entries = @($parsed)
}
elseif ($parsed.PSObject.Properties.Name -contains 'automations') {
    $entries = @($parsed.automations)
}

function Get-CategoryPathSegments {
    param([Parameter(Mandatory = $true)][object]$Entry)

    if (-not ($Entry.PSObject.Properties.Name -contains 'categoryPath')) {
        return @()
    }

    $value = $Entry.categoryPath
    if (-not ($value -is [array])) {
        return @()
    }

    return @(
        @($value) |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { $_ }
    )
}

function Parse-StoragePathFromCommand {
    param([Parameter(Mandatory = $true)][string]$Command)

    $trimmed = $Command.Trim()
    if ($trimmed -match "-Path\s+'((?:''|[^'])*)'") {
        return $Matches[1].Replace("''", "'")
    }

    if ($trimmed -match "-Root\s+'((?:''|[^'])*)'") {
        return $Matches[1].Replace("''", "'")
    }

    return ''
}

$flowMap = @{}
$managedAliases = @('Run Monthly Flow', 'Preview Storage', 'Ensure New Month Folder')
foreach ($entry in $entries) {
    if ($null -eq $entry) { continue }

    $categoryPath = @(Get-CategoryPathSegments -Entry $entry)
    $flowName = if ($categoryPath.Count -gt 0) { $categoryPath[0] } else { '' }
    $alias = if ($entry.PSObject.Properties.Name -contains 'alias') { ([string]$entry.alias).Trim() } else { '' }
    $isManagedFlowEntry = ($flowName -and ($flowName -ne 'tomatoflow-setup') -and ($managedAliases -contains $alias))

    if (-not $isManagedFlowEntry) { continue }

    if (-not $flowName) { continue }

    if (-not $flowMap.ContainsKey($flowName)) {
        $commandValue = if ($entry.PSObject.Properties.Name -contains 'command') { ([string]$entry.command) } else { '' }
        $storagePath = Parse-StoragePathFromCommand -Command $commandValue

        $flowMap[$flowName] = [pscustomobject]@{
            Name = $flowName
            StoragePath = $storagePath
        }
    }
}

$flows = @($flowMap.Values | Sort-Object Name)
if (-not $flows -or $flows.Count -eq 0) {
    Write-Host 'No configured tomatoflows found yet.' -ForegroundColor Yellow
}
else {
    Write-Host 'Configured tomatoflows:' -ForegroundColor Cyan
    foreach ($flow in $flows) {
        Write-Host ("- {0} -> {1}" -f $flow.Name, $flow.StoragePath) -ForegroundColor Gray
    }
}

Write-Output (New-ToolResult -Status 'Listed' -Data @{
        MetadataPath = $metadataFilePath
        FlowCount = $flows.Count
        Flows = $flows
    })

exit 0
