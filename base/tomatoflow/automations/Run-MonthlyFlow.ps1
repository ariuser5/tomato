# -----------------------------------------------------------------------------
# Run-MonthlyFlow.ps1
# -----------------------------------------------------------------------------
# Runs the unified tomatoflow for a configured storage path.
#
# Flow steps:
#   1) Create next month folder and copy template artifacts.
#   2) Conclude previous month by removing underscore prefix.
#   3) Label files in the newly created month folder.
#   4) Create archives grouped by labels.
#   5) Optionally open project-specific draft automation if available.
# -----------------------------------------------------------------------------
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$FlowName,

    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter()]
    [ValidateSet('Auto', 'Local', 'Remote')]
    [string]$PathType = 'Auto',

    [Parameter()]
    [int]$StartYear = (Get-Date).Year,

    [Parameter()]
    [string]$NewFolderPrefix = '_',

    [Parameter()]
    [string]$LabelsFilePath
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$organizationDir = Join-Path $scriptDir '..\organization'

$createMonthlyReportScript = Join-Path $organizationDir 'Create-MonthlyReport.ps1'
$concludeScript = Join-Path $organizationDir 'Conclude-PreviousMonthFolder.ps1'
$labelScript = Join-Path $organizationDir 'Label-Files.ps1'
$archiveScript = Join-Path $organizationDir 'Archive-FilesByLabel.ps1'
$draftScript = Join-Path $scriptDir 'Create-MailerDraft.ps1'

$resultUtilsModule = Join-Path $scriptDir '..\..\utils\common\ResultUtils.psm1'
Import-Module $resultUtilsModule -Force

foreach ($required in @($createMonthlyReportScript, $concludeScript, $labelScript, $archiveScript)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing required script: $required"
    }
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Tomatoflow Monthly Run: $FlowName" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Storage: $Path" -ForegroundColor Gray
Write-Host ''

$createdPath = $null

Write-Host '[1/5] Creating next month folder and template artifacts...' -ForegroundColor Yellow
$step1Output = & $createMonthlyReportScript -Path $Path -PathType $PathType -StartYear $StartYear -NewFolderPrefix $NewFolderPrefix
if ($LASTEXITCODE -ne 0) {
    throw "Create-MonthlyReport failed with exit code $LASTEXITCODE"
}

foreach ($item in @($step1Output)) {
    if ($item -is [pscustomobject] -and $item.PSObject.Properties.Name -contains 'Status' -and $item.PSObject.Properties.Name -contains 'Path') {
        if ("$($item.Status)" -eq 'Initialized') {
            $createdPath = "$($item.Path)"
            break
        }
    }
}

if (-not $createdPath) {
    throw 'Monthly flow could not determine newly created month folder path.'
}

Write-Host "[2/5] Concluding previous month folder..." -ForegroundColor Yellow
$step2Output = & $concludeScript -Path $Path -PathType $PathType
if ($LASTEXITCODE -ne 0) {
    throw "Conclude-PreviousMonthFolder failed with exit code $LASTEXITCODE"
}

Write-Host "[3/5] Labeling files in current month folder..." -ForegroundColor Yellow
$labelArgs = @{
    Path = $createdPath
    PathType = $PathType
}
if ($LabelsFilePath) {
    $labelArgs.LabelsFilePath = $LabelsFilePath
}
$step3Output = & $labelScript @labelArgs
if ($LASTEXITCODE -ne 0) {
    throw "Label-Files failed with exit code $LASTEXITCODE"
}

Write-Host "[4/5] Archiving files by label..." -ForegroundColor Yellow
$step4Output = & $archiveScript -Path $createdPath -PathType $PathType
if ($LASTEXITCODE -ne 0) {
    throw "Archive-FilesByLabel failed with exit code $LASTEXITCODE"
}

$runDraft = $false
if ($Host.UI -and $Host.UI.RawUI) {
    $draftAnswer = Read-Host '[5/5] Open draft email automation now? [y/N]'
    $runDraft = ([string]$draftAnswer).Trim().Equals('y', [System.StringComparison]::OrdinalIgnoreCase)
}

if ($runDraft) {
    if (Test-Path -LiteralPath $draftScript -PathType Leaf) {
        Write-Host 'Opening draft email automation...' -ForegroundColor Yellow
        $null = & $draftScript
        if ($LASTEXITCODE -ne 0) {
            Write-Host 'Draft automation failed. Monthly flow completed, but draft step failed.' -ForegroundColor Red
        }
    }
    else {
        Write-Host 'Draft automation script is not configured in this repository yet. Skipping draft step.' -ForegroundColor DarkYellow
    }
}
else {
    Write-Host '[5/5] Skipped draft email automation.' -ForegroundColor DarkYellow
}

Write-Host ''
Write-Host '========================================' -ForegroundColor Green
Write-Host '✓ Monthly tomatoflow completed' -ForegroundColor Green
Write-Host '========================================' -ForegroundColor Green
Write-Host "Current month folder: $createdPath" -ForegroundColor Gray

Write-Output (New-ToolResult -Status 'Completed' -Data @{
        FlowName = $FlowName
        BasePath = $Path
        CurrentMonthPath = $createdPath
        PreviousMonthResult = @($step2Output)
        LabelResult = @($step3Output)
        ArchiveResult = @($step4Output)
        DraftRequested = $runDraft
    })

exit 0
