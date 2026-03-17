# -----------------------------------------------------------------------------
# Remove-Tomatoflow.ps1
# -----------------------------------------------------------------------------
# Removes one configured flow from local tomatoflow metadata.
# -----------------------------------------------------------------------------
[CmdletBinding()]
param(
    [Parameter()]
    [string]$FlowName
)

$ErrorActionPreference = 'Stop'

$resultUtilsModule = Join-Path $PSScriptRoot '..\..\utils\common\ResultUtils.psm1'
Import-Module $resultUtilsModule -Force

$localAppData = ([string]$env:LOCALAPPDATA ?? '').Trim()
if (-not $localAppData) {
    throw 'LOCALAPPDATA is not set.'
}

$metadataFilePath = Join-Path (Join-Path $localAppData 'tomato') 'tomatoflow-meta.json'
if (-not (Test-Path -LiteralPath $metadataFilePath -PathType Leaf)) {
    throw "Metadata file not found: $metadataFilePath"
}

$resolvedFlowName = ([string]$FlowName ?? '').Trim()
if (-not $resolvedFlowName -and $Host.UI -and $Host.UI.RawUI) {
    $resolvedFlowName = (Read-Host 'Flow name to remove').Trim()
}
if (-not $resolvedFlowName) {
    throw 'Flow name is required.'
}

$raw = Get-Content -LiteralPath $metadataFilePath -Raw -Encoding UTF8
$parsed = $raw | ConvertFrom-Json -ErrorAction Stop
$entries = @()
if ($parsed -is [array]) {
    $entries = @($parsed)
}
elseif ($parsed.PSObject.Properties.Name -contains 'automations') {
    $entries = @($parsed.automations)
}

$kept = @()
$removedCount = 0
foreach ($entry in $entries) {
    if ($null -eq $entry) { continue }

    $isManaged = (
        (($entry.PSObject.Properties.Name -contains 'managedBy') -and (("$($entry.managedBy)" -eq 'tomatoflow-configure') -or ("$($entry.managedBy)" -eq 'tomatoflow-setup'))) -or
        (($entry.PSObject.Properties.Name -contains 'generatedBy') -and ("$($entry.generatedBy)" -eq 'tomatoflow-setup'))
    )
    $isSameFlow = ($entry.PSObject.Properties.Name -contains 'flowName') -and ("$($entry.flowName)" -eq $resolvedFlowName)

    if ($isManaged -and $isSameFlow) {
        $removedCount++
        continue
    }

    $kept += $entry
}

$payload = [ordered]@{
    automations = $kept
}

$json = $payload | ConvertTo-Json -Depth 12
Set-Content -LiteralPath $metadataFilePath -Value $json -Encoding UTF8

if ($removedCount -eq 0) {
    Write-Host "No configured entries found for flow '$resolvedFlowName'." -ForegroundColor Yellow
}
else {
    Write-Host "✓ Removed flow '$resolvedFlowName' from local metadata." -ForegroundColor Green
}

Write-Output (New-ToolResult -Status 'Removed' -Data @{
        FlowName = $resolvedFlowName
        RemovedAutomationCount = $removedCount
        MetadataPath = $metadataFilePath
    })

exit 0
