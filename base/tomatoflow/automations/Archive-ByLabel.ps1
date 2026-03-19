# -----------------------------------------------------------------------------
# Archive-ByLabel.ps1
# -----------------------------------------------------------------------------
# Tomatoflow automation wrapper for organization/Archive-FilesByLabel.ps1.
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
    [string]$ArchiveDestinationPath,

    [Parameter()]
    [string]$ArchiveExtension = 'zip',

    [Parameter()]
    [string]$SevenZipExe = '7z',

    [Parameter()]
    [string]$ExcludeNameRegex,

    [Parameter()]
    [switch]$IncludeUnlabeled,

    [Parameter()]
    [string]$UnlabeledGroupName = 'UNLABELED',

    [Parameter()]
    [switch]$Overwrite
)

$ErrorActionPreference = 'Stop'

$flowTargetUtilsModule = Join-Path $PSScriptRoot '.\modules\FlowTargetUtils.psm1'
Import-Module $flowTargetUtilsModule -Force

$resultUtilsModule = Join-Path $PSScriptRoot '..\..\utils\common\ResultUtils.psm1'
Import-Module $resultUtilsModule -Force

$targetScript = Join-Path $PSScriptRoot '..\organization\Archive-FilesByLabel.ps1'
$targetScript = (Resolve-Path -LiteralPath $targetScript -ErrorAction Stop).Path

$target = Resolve-FlowTargetPath -RootPath $Path -PathType $PathType -Subfolder $Subfolder -PromptLabel 'archive by label'
if ($target.Status -eq 'Aborted') {
    Write-Host 'Archive by label action aborted (ESC).' -ForegroundColor DarkYellow
    Write-Output (New-ToolResult -Status 'Aborted' -Data @{
            RootPath = $Path
            PathType = $PathType
            Action = 'Archive By Label'
        })
    exit 0
}

if ($target.UsedFallback) {
    Write-Host "Using latest month folder: $($target.SubfolderName)" -ForegroundColor Gray
}

$invokeArgs = @{
    Path = $target.TargetPath
    PathType = $PathType
    ArchiveExtension = $ArchiveExtension
    SevenZipExe = $SevenZipExe
    UnlabeledGroupName = $UnlabeledGroupName
    IncludeUnlabeled = $IncludeUnlabeled
    Overwrite = $Overwrite
}
if ($ArchiveDestinationPath) { $invokeArgs.ArchiveDestinationPath = $ArchiveDestinationPath }
if ($ExcludeNameRegex) { $invokeArgs.ExcludeNameRegex = $ExcludeNameRegex }

& $targetScript @invokeArgs
