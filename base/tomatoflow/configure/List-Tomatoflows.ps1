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

$flowMap = @{}
foreach ($entry in $entries) {
    if ($null -eq $entry) { continue }

    $isManaged = (
        (($entry.PSObject.Properties.Name -contains 'managedBy') -and (("$($entry.managedBy)" -eq 'tomatoflow-configure') -or ("$($entry.managedBy)" -eq 'tomatoflow-setup'))) -or
        (($entry.PSObject.Properties.Name -contains 'generatedBy') -and ("$($entry.generatedBy)" -eq 'tomatoflow-setup'))
    )
    if (-not $isManaged) { continue }

    $flowName = ''
    if ($entry.PSObject.Properties.Name -contains 'flowName') {
        $flowName = ("$($entry.flowName)").Trim()
    }

    if (-not $flowName) { continue }

    if (-not $flowMap.ContainsKey($flowName)) {
        $storagePath = ''
        if ($entry.PSObject.Properties.Name -contains 'storagePath') {
            $storagePath = "$($entry.storagePath)"
        }

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
