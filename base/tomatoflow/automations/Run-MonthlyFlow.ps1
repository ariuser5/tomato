# -----------------------------------------------------------------------------
# Run-MonthlyFlow.ps1
# -----------------------------------------------------------------------------
# Runs the unified tomatoflow for a configured storage path.
#
# Flow steps:
#   1) Create next month folder and copy template artifacts.
#   2) Label files in the newly created month folder.
#   3) Create archives grouped by labels.
#   4) Optionally open project-specific draft automation if available.
#   5) Conclude previous month by removing underscore prefix.
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
$draftScript = Join-Path $scriptDir 'Create-DraftEmail.ps1'

$pathModule = Join-Path $scriptDir '..\..\utils\PathUtils.psm1'
Import-Module $pathModule -Force

$monthUtilsModule = Join-Path $organizationDir 'modules\MonthUtils.psm1'
Import-Module $monthUtilsModule -Force

$commandUtilsModule = Join-Path $scriptDir '..\..\utils\common\CommandUtils.psm1'
Import-Module $commandUtilsModule -Force

$resultUtilsModule = Join-Path $scriptDir '..\..\utils\common\ResultUtils.psm1'
Import-Module $resultUtilsModule -Force

foreach ($required in @($createMonthlyReportScript, $concludeScript, $labelScript, $archiveScript)) {
    if (-not (Test-Path -LiteralPath $required -PathType Leaf)) {
        throw "Missing required script: $required"
    }
}

function Confirm-StepExecution {
    param(
        [Parameter(Mandatory = $true)][int]$Step,
        [Parameter(Mandatory = $true)][string]$Title
    )

    while ($true) {
        $answer = Read-Host ("[{0}/5] {1} Proceed with this step? [Y/n]" -f $Step, $Title)
        $choice = ([string]$answer ?? '').Trim().ToLowerInvariant()

        if (-not $choice -or $choice -eq 'y' -or $choice -eq 'yes') {
            return $true
        }
        if ($choice -eq 'n' -or $choice -eq 'no' -or $choice -eq 's' -or $choice -eq 'skip') {
            return $false
        }

        Write-Host "Please answer y (proceed) or n (skip)." -ForegroundColor Yellow
    }
}

function Resolve-CurrentMonthFolderPath {
    param(
        [Parameter(Mandatory = $true)][string]$BasePath,
        [Parameter(Mandatory = $true)][string]$ResolvedPathType
    )

    $baseInfo = Resolve-UnifiedPath -Path $BasePath -PathType $ResolvedPathType

    $existingDirs = @()
    if ($baseInfo.PathType -eq 'Remote') {
        Assert-RcloneAvailable
        $existingDirs = @(
            Invoke-Rclone -Arguments @('lsf', $baseInfo.Normalized, '--dirs-only') -ErrorMessage "Failed to list remote directory '$($baseInfo.Normalized)'."
        )
        $existingDirs = @(
            $existingDirs |
                Where-Object { $_ -ne $null -and $_ -ne '' } |
                ForEach-Object { $_.TrimEnd('/') }
        )
    }
    else {
        if (-not (Test-Path -LiteralPath $baseInfo.LocalPath -PathType Container)) {
            throw "Storage path does not exist: $($baseInfo.LocalPath)"
        }

        $existingDirs = @(
            Get-ChildItem -LiteralPath $baseInfo.LocalPath -Directory -ErrorAction Stop |
                Select-Object -ExpandProperty Name
        )
    }

    $latestMonthName = Get-LastMonthValue -Values $existingDirs -SkipInvalid
    if (-not $latestMonthName) {
        return $null
    }

    return (Join-UnifiedPath -Base $baseInfo.Normalized -Child $latestMonthName -PathType $baseInfo.PathType)
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Tomatoflow Monthly Run: $FlowName" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Storage: $Path" -ForegroundColor Gray
Write-Host ''

$createdPath = $null
$currentMonthPath = $null
$step1Output = @()
$step2Output = @()
$step3Output = @()
$step4Requested = $false
$step4Executed = $false
$step4Succeeded = $false
$step5Output = @()

$currentMonthPath = Resolve-CurrentMonthFolderPath -BasePath $Path -ResolvedPathType $PathType
if ($currentMonthPath) {
    Write-Host "Current month folder before step 1: $currentMonthPath" -ForegroundColor Gray
}
else {
    Write-Host 'Current month folder before step 1: (none found)' -ForegroundColor DarkYellow
}

if (Confirm-StepExecution -Step 1 -Title 'Creating next month folder and template artifacts.') {
    Write-Host '[1/5] Creating next month folder and template artifacts...' -ForegroundColor Yellow
    $step1Output = @(& $createMonthlyReportScript -Path $Path -PathType $PathType -StartYear $StartYear -NewFolderPrefix $NewFolderPrefix)
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

    $currentMonthPath = $createdPath
}
else {
    Write-Host '[1/5] Skipped creating next month folder and template artifacts.' -ForegroundColor DarkYellow
}

if (Confirm-StepExecution -Step 2 -Title 'Labeling files in current month folder.') {
    if (-not $currentMonthPath) {
        Write-Host '[2/5] Skipped labeling: no current month folder could be resolved.' -ForegroundColor DarkYellow
    }
    else {
        Write-Host '[2/5] Labeling files in current month folder...' -ForegroundColor Yellow
        $labelArgs = @{
            Path = $currentMonthPath
            PathType = $PathType
        }
        if ($LabelsFilePath) {
            $labelArgs.LabelsFilePath = $LabelsFilePath
        }

        $step2Output = @(& $labelScript @labelArgs)
        if ($LASTEXITCODE -ne 0) {
            throw "Label-Files failed with exit code $LASTEXITCODE"
        }
    }
}
else {
    Write-Host '[2/5] Skipped labeling files.' -ForegroundColor DarkYellow
}

if (Confirm-StepExecution -Step 3 -Title 'Archiving files by label.') {
    if (-not $currentMonthPath) {
        Write-Host '[3/5] Skipped archiving: no current month folder could be resolved.' -ForegroundColor DarkYellow
    }
    else {
        Write-Host '[3/5] Archiving files by label...' -ForegroundColor Yellow
        $step3Output = @(& $archiveScript -Path $currentMonthPath -PathType $PathType)
        if ($LASTEXITCODE -ne 0) {
            throw "Archive-FilesByLabel failed with exit code $LASTEXITCODE"
        }
    }
}
else {
    Write-Host '[3/5] Skipped archiving files by label.' -ForegroundColor DarkYellow
}

if (Confirm-StepExecution -Step 4 -Title 'Creating draft email automation.') {
    $step4Requested = $true
    if (Test-Path -LiteralPath $draftScript -PathType Leaf) {
        Write-Host '[4/5] Creating draft email automation...' -ForegroundColor Yellow
        $step4Executed = $true
        $null = & $draftScript
        if ($LASTEXITCODE -ne 0) {
            throw "Create-DraftEmail failed with exit code $LASTEXITCODE"
        }
        $step4Succeeded = $true
    }
    else {
        Write-Host '[4/5] Skipped draft email automation: script is not configured in this repository yet.' -ForegroundColor DarkYellow
    }
}
else {
    Write-Host '[4/5] Skipped draft email automation.' -ForegroundColor DarkYellow
}

if (Confirm-StepExecution -Step 5 -Title 'Concluding previous month folder.') {
    Write-Host '[5/5] Concluding previous month folder...' -ForegroundColor Yellow
    $step5Output = @(& $concludeScript -Path $Path -PathType $PathType)
    if ($LASTEXITCODE -ne 0) {
        throw "Conclude-PreviousMonthFolder failed with exit code $LASTEXITCODE"
    }
}
else {
    Write-Host '[5/5] Skipped concluding previous month folder.' -ForegroundColor DarkYellow
}

Write-Host ''
Write-Host '========================================' -ForegroundColor Green
Write-Host '✓ Monthly tomatoflow completed' -ForegroundColor Green
Write-Host '========================================' -ForegroundColor Green
if ($currentMonthPath) {
    Write-Host "Current month folder: $currentMonthPath" -ForegroundColor Gray
}
else {
    Write-Host 'Current month folder: (not found)' -ForegroundColor Gray
}

Write-Output (New-ToolResult -Status 'Completed' -Data @{
        FlowName = $FlowName
        BasePath = $Path
        CurrentMonthPath = $currentMonthPath
        CreatedMonthPath = $createdPath
        CreateMonthlyReportResult = @($step1Output)
        LabelResult = @($step2Output)
        ArchiveResult = @($step3Output)
        DraftRequested = $step4Requested
        DraftExecuted = $step4Executed
        DraftSucceeded = $step4Succeeded
        PreviousMonthResult = @($step5Output)
    })

exit 0
