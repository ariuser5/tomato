# -----------------------------------------------------------------------------
# Create-DraftEmail.ps1
# -----------------------------------------------------------------------------
# Tomatoflow automation wrapper for automations/scripts/Create-DraftEmail.ps1.
#
# Behavior:
# - Works from flow root path and asks for a target subfolder.
# - Entering empty/whitespace uses the latest month folder as fallback.
# - Pressing ESC aborts the action.
# - Delegates to non-interactive script implementation in ./scripts.
# -----------------------------------------------------------------------------

[CmdletBinding()]
param(
    [Parameter()]
    [string]$FlowName,

    [Parameter(Mandatory = $true)]
    [Alias('Path')]
    [string]$StoragePath,

    [Parameter()]
    [ValidateSet('Auto', 'Local', 'Remote')]
    [string]$PathType = 'Auto',

    [Parameter()]
    [string]$Subfolder
)

$ErrorActionPreference = 'Stop'

$flowTargetUtilsModule = Join-Path $PSScriptRoot '.\modules\FlowTargetUtils.psm1'
Import-Module $flowTargetUtilsModule -Force

$resultUtilsModule = Join-Path $PSScriptRoot '..\..\utils\common\ResultUtils.psm1'
Import-Module $resultUtilsModule -Force

$targetScript = Join-Path $PSScriptRoot '.\scripts\Create-DraftEmail.ps1'
$targetScript = (Resolve-Path -LiteralPath $targetScript -ErrorAction Stop).Path

$target = Resolve-FlowTargetPath -RootPath $StoragePath -PathType $PathType -Subfolder $Subfolder -PromptLabel 'draft email'
if ($target.Status -eq 'Aborted') {
    Write-Host 'Draft email action aborted (ESC).' -ForegroundColor DarkYellow
    Write-Output (New-ToolResult -Status 'Aborted' -Data @{
            FlowName = $FlowName
            RootPath = $StoragePath
            PathType = $PathType
            Action = 'Create Draft Email'
        })
    exit 0
}

if ($target.UsedFallback) {
    Write-Host "Using latest month folder: $($target.SubfolderName)" -ForegroundColor Gray
}

$tomatoRoot = ([string]$env:TOMATO_ROOT ?? '').Trim()
$customDraftScript = if ($tomatoRoot) {
    Join-Path $tomatoRoot 'automations\Create-DraftEmail.ps1'
}
else {
    $null
}

if ($customDraftScript -and (Test-Path -LiteralPath $customDraftScript -PathType Leaf)) {
    Write-Host "Running custom draft automation: $customDraftScript" -ForegroundColor Yellow

    $invokeArgs = @{}
    if ($FlowName) { $invokeArgs.FlowName = $FlowName }
    $invokeArgs.Path = $target.TargetPath
    if ($PathType) { $invokeArgs.PathType = $PathType }

    $invocationOutput = $null
    try {
        $invocationOutput = & $customDraftScript @invokeArgs
    }
    catch [System.Management.Automation.ParameterBindingException] {
        # Compatibility fallback for custom scripts with different signatures.
        $invocationOutput = & $customDraftScript
    }

    if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    if ($null -ne $invocationOutput) {
        Write-Output $invocationOutput
    }

    Write-Output (New-ToolResult -Status 'Completed' -Data @{
            FlowName = $FlowName
            RootPath = $StoragePath
            Path = $target.TargetPath
            Subfolder = $target.SubfolderName
            PathType = $PathType
            Script = $customDraftScript
        })
    exit 0
}

$invokeScriptArgs = @{
    Path = $target.TargetPath
    PathType = $PathType
    DefaultAttachmentPatterns = '[Aa]rchives/'
}

& $targetScript @invokeScriptArgs
