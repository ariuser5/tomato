# -----------------------------------------------------------------------------
# Run-MonthlyFlow.ps1
# -----------------------------------------------------------------------------
# Runs the unified tomatoflow for a configured storage path.
#
# Flow steps:
#   1) Select month folder to process (latest or custom existing folder).
#   2) Label files in the selected month folder.
#   3) Create archives grouped by labels.
#   4) Optionally open project-specific draft automation if available.
#   5) Conclude worked month folder by removing underscore prefix.
#   6) Create next month folder and copy template artifacts.
# -----------------------------------------------------------------------------
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [Alias('Path')]
    [string]$StoragePath,

    [Parameter()]
    [ValidateSet('Auto', 'Local', 'Remote')]
    [string]$PathType = 'Auto',

    [Parameter()]
    [int]$StartYear = (Get-Date).Year,

    [Parameter()]
    [string]$NewFolderPrefix = '_',

    [Parameter()]
    [string]$LabelsFilePath,

    [Parameter()]
    [string]$MailerParamFile,

    [Parameter()]
    [string]$ArtifactsSourcePath,

    [Parameter()]
    [string]$FlowName
)

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptsDir = Join-Path $scriptDir '.\scripts'

$createMonthlyReportScript = Join-Path $scriptsDir 'Create-MonthlyReport.ps1'
$concludeScript = Join-Path $scriptsDir 'Conclude-MonthFolder.ps1'
$labelScript = Join-Path $scriptsDir 'Label-Files.ps1'
$archiveScript = Join-Path $scriptsDir 'Archive-ByLabel.ps1'
$draftScript = Join-Path $scriptsDir 'Create-DraftEmail.ps1'

$flowTargetUtilsModule = Join-Path $scriptDir '.\modules\FlowTargetUtils.psm1'
Import-Module $flowTargetUtilsModule -Force

$pathUtilsModule = Join-Path $scriptDir '..\..\utils\PathUtils.psm1'
Import-Module $pathUtilsModule -Force

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

    $prompt = "[{0}/6] {1} Proceed with this step? [Yes/No] (default: Yes, ESC = abort)" -f $Step, $Title

    while ($true) {
        $response = Read-InputWithEsc -Prompt $prompt
        if ($response.Status -eq 'Escaped') {
            return 'Abort'
        }

        $choice = ([string]$response.Value ?? '').Trim().ToLowerInvariant()

        if (-not $choice -or $choice -eq 'y' -or $choice -eq 'yes') {
            return 'Run'
        }
        if ($choice -eq 'n' -or $choice -eq 'no') {
            return 'Skip'
        }

        Write-Host "Please answer Yes or No." -ForegroundColor Yellow
    }
}

function Test-NonZeroExitCode {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$ExitCode
    )

    if ($null -eq $ExitCode) {
        return $false
    }

    return ([int]$ExitCode -ne 0)
}

function Resolve-FlowName {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$InputName
    )

    $resolved = ([string]$InputName ?? '').Trim()
    if ($resolved) {
        return $resolved
    }

    return ('tomatoflow-{0}' -f (Get-Date -Format 'yyyyMMdd-HHmmssss'))
}

function Resolve-MailerParamFilePath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$InputPath
    )

    $raw = ([string]$InputPath ?? '').Trim()
    if (-not $raw) {
        return ''
    }

    $tomatoRoot = ([string]$env:TOMATO_ROOT ?? '').Trim()
    $expanded = $raw
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

function Confirm-YesNoOrAbort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt
    )

    while ($true) {
        $response = Read-InputWithEsc -Prompt $Prompt
        if ($response.Status -eq 'Escaped') {
            return 'Abort'
        }

        $choice = ([string]$response.Value ?? '').Trim().ToLowerInvariant()
        if (-not $choice -or $choice -eq 'y' -or $choice -eq 'yes') {
            return 'Yes'
        }
        if ($choice -eq 'n' -or $choice -eq 'no') {
            return 'No'
        }

        Write-Host 'Please answer Yes or No.' -ForegroundColor Yellow
    }
}

function Test-UnifiedDirectoryExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter()]
        [ValidateSet('Auto', 'Local', 'Remote')]
        [string]$PathType = 'Auto'
    )

    $resolved = Resolve-UnifiedPath -Path $Path -PathType $PathType
    if ($resolved.PathType -eq 'Remote') {
        try {
            $null = Invoke-Rclone -Arguments @('lsf', $resolved.Normalized, '--dirs-only', '--max-depth', '1') -ErrorMessage "Failed to verify remote path '$($resolved.Normalized)'."
            return $true
        }
        catch {
            return $false
        }
    }

    return (Test-Path -LiteralPath $resolved.LocalPath -PathType Container)
}

function Resolve-MonthFolderToProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter()]
        [ValidateSet('Auto', 'Local', 'Remote')]
        [string]$PathType = 'Auto'
    )

    $rootInfo = Resolve-UnifiedPath -Path $RootPath -PathType $PathType
    $latestMonthPath = Get-LatestMonthTargetPath -RootPath $RootPath -PathType $PathType
    $latestMonthName = if ($latestMonthPath) { Split-Path -Leaf $latestMonthPath } else { $null }

    if ($latestMonthPath) {
        $decision = Confirm-YesNoOrAbort -Prompt ("[1/6] Use latest month folder '{0}'? [Yes/No] (default: Yes, ESC = abort)" -f $latestMonthName)
        if ($decision -eq 'Abort') {
            return [pscustomobject]@{
                Status = 'Aborted'
                Path = $null
            }
        }

        if ($decision -eq 'Yes') {
            return [pscustomobject]@{
                Status = 'Resolved'
                Path = $latestMonthPath
            }
        }
    }
    else {
        Write-Host '[1/6] No latest month folder found. Please enter an existing folder name to process.' -ForegroundColor DarkYellow
    }

    $nameResponse = Read-InputWithEsc -Prompt '[1/6] Enter month folder name to process (must already exist, ESC = abort)'
    if ($nameResponse.Status -eq 'Escaped') {
        return [pscustomobject]@{
            Status = 'Aborted'
            Path = $null
        }
    }

    $folderName = ([string]$nameResponse.Value ?? '').Trim()
    if (-not $folderName) {
        throw 'Month folder name is required when not using the latest month folder.'
    }

    $candidatePath = Join-UnifiedPath -Base $rootInfo.Normalized -Child $folderName -PathType $rootInfo.PathType
    if (-not (Test-UnifiedDirectoryExists -Path $candidatePath -PathType $rootInfo.PathType)) {
        throw "Selected month folder does not exist: $candidatePath"
    }

    return [pscustomobject]@{
        Status = 'Resolved'
        Path = $candidatePath
    }
}

$resolvedFlowName = Resolve-FlowName -InputName $FlowName
$resolvedMailerParamFile = Resolve-MailerParamFilePath -InputPath $MailerParamFile

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Tomatoflow Monthly Run: $resolvedFlowName" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Storage: $StoragePath" -ForegroundColor Gray
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

function Exit-AbortedMonthlyFlow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [int]$BeforeStep
    )

    Write-Host ''
    Write-Host "Monthly tomatoflow aborted by user before step $BeforeStep (ESC)." -ForegroundColor DarkYellow
    Write-Output (New-ToolResult -Status 'Aborted' -Data @{
        FlowName = $resolvedFlowName
        BasePath = $StoragePath
        CurrentMonthPath = $currentMonthPath
        CreatedMonthPath = $createdPath
        CreateMonthlyReportResult = @($step1Output)
        LabelResult = @($step2Output)
        ArchiveResult = @($step3Output)
        DraftRequested = $step4Requested
        DraftExecuted = $step4Executed
        DraftSucceeded = $step4Succeeded
        ConcludeMonthFolderResult = @($step5Output)
        AbortedBeforeStep = $BeforeStep
    })
    exit 0
}

function Confirm-RetryOrSkip {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][int]$Step,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )

    Write-Host ("[{0}/6] {1} failed: {2}" -f $Step, $Title, $FailureMessage) -ForegroundColor Red

    $prompt = "[{0}/6] Retry this step or skip it? [Retry/Skip] (default: Retry, ESC = abort)" -f $Step
    while ($true) {
        $response = Read-InputWithEsc -Prompt $prompt
        if ($response.Status -eq 'Escaped') {
            return 'Abort'
        }

        $choice = ([string]$response.Value ?? '').Trim().ToLowerInvariant()
        if (-not $choice -or $choice -eq 'r' -or $choice -eq 'retry' -or $choice -eq 'y' -or $choice -eq 'yes') {
            return 'Retry'
        }

        if ($choice -eq 's' -or $choice -eq 'skip' -or $choice -eq 'n' -or $choice -eq 'no') {
            return 'Skip'
        }

        Write-Host 'Please answer Retry or Skip.' -ForegroundColor Yellow
    }
}

$monthSelection = Resolve-MonthFolderToProcess -RootPath $StoragePath -PathType $PathType
if ($monthSelection.Status -eq 'Aborted') {
    Exit-AbortedMonthlyFlow -BeforeStep 1
}
$currentMonthPath = $monthSelection.Path
Write-Host "[1/6] Selected month folder: $currentMonthPath" -ForegroundColor Gray

$step2FirstPrompt = $true
while ($true) {
    if ($step2FirstPrompt) {
        $step2Decision = Confirm-StepExecution -Step 2 -Title 'Labeling files in selected month folder.'
        if ($step2Decision -eq 'Abort') {
            Exit-AbortedMonthlyFlow -BeforeStep 2
        }
        if ($step2Decision -eq 'Skip') {
            Write-Host '[2/6] Skipped labeling files.' -ForegroundColor DarkYellow
            break
        }

        $step2FirstPrompt = $false
    }

    try {
        if (-not $currentMonthPath) {
            Write-Host '[2/6] Skipped labeling: no selected month folder is available.' -ForegroundColor DarkYellow
        }
        else {
            Write-Host '[2/6] Labeling files in selected month folder...' -ForegroundColor Yellow
            $labelArgs = @{
                Path = $currentMonthPath
                PathType = $PathType
            }
            if ($LabelsFilePath) {
                $labelArgs.LabelsFilePath = $LabelsFilePath
            }

            $step2Output = @(& $labelScript @labelArgs)
            if (Test-NonZeroExitCode -ExitCode $LASTEXITCODE) {
                throw "Label-Files failed with exit code $LASTEXITCODE"
            }
        }

        break
    }
    catch {
        $retryDecision = Confirm-RetryOrSkip -Step 2 -Title 'Labeling files in selected month folder.' -FailureMessage $_.Exception.Message
        if ($retryDecision -eq 'Abort') {
            Exit-AbortedMonthlyFlow -BeforeStep 2
        }
        if ($retryDecision -eq 'Skip') {
            Write-Host '[2/6] Skipped labeling files after failure.' -ForegroundColor DarkYellow
            break
        }
    }
}

$step3FirstPrompt = $true
while ($true) {
    if ($step3FirstPrompt) {
        $step3Decision = Confirm-StepExecution -Step 3 -Title 'Archiving files by label.'
        if ($step3Decision -eq 'Abort') {
            Exit-AbortedMonthlyFlow -BeforeStep 3
        }
        if ($step3Decision -eq 'Skip') {
            Write-Host '[3/6] Skipped archiving files by label.' -ForegroundColor DarkYellow
            break
        }

        $step3FirstPrompt = $false
    }

    try {
        if (-not $currentMonthPath) {
            Write-Host '[3/6] Skipped archiving: no selected month folder is available.' -ForegroundColor DarkYellow
        }
        else {
            Write-Host '[3/6] Archiving files by label...' -ForegroundColor Yellow
            $step3Output = @(& $archiveScript -Path $currentMonthPath -PathType $PathType)
            if (Test-NonZeroExitCode -ExitCode $LASTEXITCODE) {
                throw "Archive-ByLabel failed with exit code $LASTEXITCODE"
            }
        }

        break
    }
    catch {
        $retryDecision = Confirm-RetryOrSkip -Step 3 -Title 'Archiving files by label.' -FailureMessage $_.Exception.Message
        if ($retryDecision -eq 'Abort') {
            Exit-AbortedMonthlyFlow -BeforeStep 3
        }
        if ($retryDecision -eq 'Skip') {
            Write-Host '[3/6] Skipped archiving files by label after failure.' -ForegroundColor DarkYellow
            break
        }
    }
}

$step4FirstPrompt = $true
while ($true) {
    if ($step4FirstPrompt) {
        $step4Decision = Confirm-StepExecution -Step 4 -Title 'Creating draft email automation.'
        if ($step4Decision -eq 'Abort') {
            Exit-AbortedMonthlyFlow -BeforeStep 4
        }
        if ($step4Decision -eq 'Skip') {
            Write-Host '[4/6] Skipped draft email automation.' -ForegroundColor DarkYellow
            break
        }

        $step4FirstPrompt = $false
    }

    try {
        $step4Requested = $true
        if (Test-Path -LiteralPath $draftScript -PathType Leaf) {
            if (-not $resolvedMailerParamFile) {
                Write-Host '[4/6] Skipped draft email automation: missing -MailerParamFile.' -ForegroundColor DarkYellow
                Write-Host "      To restore this step, configure a valid mailer param file in automation args, for example: -MailerParamFile '`$TOMATO_ROOT/base/resources/mailer-sample.json'." -ForegroundColor DarkYellow
            }
            elseif (-not (Test-Path -LiteralPath $resolvedMailerParamFile -PathType Leaf)) {
                Write-Host "[4/6] Skipped draft email automation: param file not found: $resolvedMailerParamFile" -ForegroundColor DarkYellow
                Write-Host "      To restore this step, update -MailerParamFile to an existing file (for example '`$TOMATO_ROOT/base/resources/mailer-sample.json')." -ForegroundColor DarkYellow
            }
            else {
                Write-Host '[4/6] Creating draft email automation...' -ForegroundColor Yellow
                $step4Executed = $true
                $targetSubfolderName = if ($currentMonthPath) { Split-Path -Leaf $currentMonthPath } else { $null }
                $draftScriptArgs = @{
                    Path = $currentMonthPath
                    MailerParamFile = $resolvedMailerParamFile
                    PathType = $PathType
                    DefaultAttachmentPatterns = '[Aa]rchives/'
                }
                $null = & $draftScript @draftScriptArgs
                if (Test-NonZeroExitCode -ExitCode $LASTEXITCODE) {
                    throw "Create-DraftEmail failed with exit code $LASTEXITCODE"
                }
                $step4Succeeded = $true
            }
        }
        else {
            Write-Host '[4/6] Skipped draft email automation: script is not configured in this repository yet.' -ForegroundColor DarkYellow
        }

        break
    }
    catch {
        $retryDecision = Confirm-RetryOrSkip -Step 4 -Title 'Creating draft email automation.' -FailureMessage $_.Exception.Message
        if ($retryDecision -eq 'Abort') {
            Exit-AbortedMonthlyFlow -BeforeStep 4
        }
        if ($retryDecision -eq 'Skip') {
            Write-Host '[4/6] Skipped draft email automation after failure.' -ForegroundColor DarkYellow
            break
        }
    }
}

$step5FirstPrompt = $true
while ($true) {
    if ($step5FirstPrompt) {
        $step5Decision = Confirm-StepExecution -Step 5 -Title 'Concluding month folder.'
        if ($step5Decision -eq 'Abort') {
            Exit-AbortedMonthlyFlow -BeforeStep 5
        }
        if ($step5Decision -eq 'Skip') {
            Write-Host '[5/6] Skipped concluding month folder.' -ForegroundColor DarkYellow
            break
        }

        $step5FirstPrompt = $false
    }

    try {
        if (-not $currentMonthPath) {
            Write-Host '[5/6] Skipped concluding month folder: no selected month folder is available.' -ForegroundColor DarkYellow
        }
        else {
            Write-Host '[5/6] Concluding month folder...' -ForegroundColor Yellow
            $targetFolderName = Split-Path -Leaf $currentMonthPath
            $step5Output = @(& $concludeScript -Path $StoragePath -PathType $PathType -TargetFolderName $targetFolderName)
        }
        if (Test-NonZeroExitCode -ExitCode $LASTEXITCODE) {
            throw "Conclude-MonthFolder failed with exit code $LASTEXITCODE"
        }

        break
    }
    catch {
        $retryDecision = Confirm-RetryOrSkip -Step 5 -Title 'Concluding month folder.' -FailureMessage $_.Exception.Message
        if ($retryDecision -eq 'Abort') {
            Exit-AbortedMonthlyFlow -BeforeStep 5
        }
        if ($retryDecision -eq 'Skip') {
            Write-Host '[5/6] Skipped concluding month folder after failure.' -ForegroundColor DarkYellow
            break
        }
    }
}

$step6FirstPrompt = $true
while ($true) {
    if ($step6FirstPrompt) {
        $step6Decision = Confirm-StepExecution -Step 6 -Title 'Creating next month folder and template artifacts.'
        if ($step6Decision -eq 'Abort') {
            Exit-AbortedMonthlyFlow -BeforeStep 6
        }
        if ($step6Decision -eq 'Skip') {
            Write-Host '[6/6] Skipped creating next month folder and template artifacts.' -ForegroundColor DarkYellow
            break
        }

        $step6FirstPrompt = $false
    }

    try {
        Write-Host '[6/6] Creating next month folder and template artifacts...' -ForegroundColor Yellow
        $createArgs = @{
            Path = $StoragePath
            PathType = $PathType
            StartYear = $StartYear
            NewFolderPrefix = $NewFolderPrefix
        }
        if (([string]$ArtifactsSourcePath ?? '').Trim()) {
            $createArgs.ArtifactsSourcePath = $ArtifactsSourcePath
        }

        $step1Output = @(& $createMonthlyReportScript @createArgs)
        if (Test-NonZeroExitCode -ExitCode $LASTEXITCODE) {
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

        break
    }
    catch {
        $retryDecision = Confirm-RetryOrSkip -Step 6 -Title 'Creating next month folder and template artifacts.' -FailureMessage $_.Exception.Message
        if ($retryDecision -eq 'Abort') {
            Exit-AbortedMonthlyFlow -BeforeStep 6
        }
        if ($retryDecision -eq 'Skip') {
            Write-Host '[6/6] Skipped creating next month folder and template artifacts after failure.' -ForegroundColor DarkYellow
            break
        }
    }
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
    FlowName = $resolvedFlowName
    BasePath = $StoragePath
    CurrentMonthPath = $currentMonthPath
    CreatedMonthPath = $createdPath
    CreateMonthlyReportResult = @($step1Output)
    LabelResult = @($step2Output)
    ArchiveResult = @($step3Output)
    DraftRequested = $step4Requested
    DraftExecuted = $step4Executed
    DraftSucceeded = $step4Succeeded
    ConcludeMonthFolderResult = @($step5Output)
})

exit 0
