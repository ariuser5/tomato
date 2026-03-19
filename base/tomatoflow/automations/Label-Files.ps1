# -----------------------------------------------------------------------------
# Label-Files.ps1
# -----------------------------------------------------------------------------
# Tomatoflow automation wrapper for organization/Label-Files.ps1.
#
# Behavior:
# - Works from flow root path and asks for a target subfolder.
# - Entering empty/whitespace uses the latest month folder as fallback.
# - Pressing ESC aborts the action.
# -----------------------------------------------------------------------------

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter()]
    [ValidateSet('Auto', 'Local', 'Remote')]
    [string]$PathType = 'Auto',

    [Parameter()]
    [string]$Subfolder,

    [Parameter()]
    [string]$ExcludeNameRegex,

    [Parameter()]
    [string]$AutoLabel,

    [Parameter()]
    [string[]]$Labels = @('INVOICE', 'BALANCE', 'EXPENSE'),

    [Parameter()]
    [string]$LabelsFilePath
)

$ErrorActionPreference = 'Stop'

$flowTargetUtilsModule = Join-Path $PSScriptRoot '.\modules\FlowTargetUtils.psm1'
Import-Module $flowTargetUtilsModule -Force

$resultUtilsModule = Join-Path $PSScriptRoot '..\..\utils\common\ResultUtils.psm1'
Import-Module $resultUtilsModule -Force

$targetScript = Join-Path $PSScriptRoot '..\organization\Label-Files.ps1'
$targetScript = (Resolve-Path -LiteralPath $targetScript -ErrorAction Stop).Path

$target = Resolve-FlowTargetPath -RootPath $Path -PathType $PathType -Subfolder $Subfolder -PromptLabel 'label files'
if ($target.Status -eq 'Aborted') {
    Write-Host 'Label files action aborted (ESC).' -ForegroundColor DarkYellow
    Write-Output (New-ToolResult -Status 'Aborted' -Data @{
            RootPath = $Path
            PathType = $PathType
            Action = 'Label Files'
        })
    exit 0
}

if ($target.UsedFallback) {
    Write-Host "Using latest month folder: $($target.SubfolderName)" -ForegroundColor Gray
}

$invokeArgs = @{
    Path = $target.TargetPath
    PathType = $PathType
    Labels = $Labels
}
if ($ExcludeNameRegex) { $invokeArgs.ExcludeNameRegex = $ExcludeNameRegex }
if ($AutoLabel) { $invokeArgs.AutoLabel = $AutoLabel }
if ($LabelsFilePath) { $invokeArgs.LabelsFilePath = $LabelsFilePath }

& $targetScript @invokeArgs
