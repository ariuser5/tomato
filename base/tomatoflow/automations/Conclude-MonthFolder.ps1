# -----------------------------------------------------------------------------
# Conclude-MonthFolder.ps1
# -----------------------------------------------------------------------------
# Tomatoflow automation wrapper for automations/scripts/Conclude-MonthFolder.ps1.
#
# Behavior:
# - Works from flow root path and asks for a target subfolder.
# - Entering empty/whitespace uses the latest month folder as fallback.
# - Pressing ESC aborts the action.
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
    [string]$Subfolder
)

$ErrorActionPreference = 'Stop'

$flowTargetUtilsModule = Join-Path $PSScriptRoot '.\modules\FlowTargetUtils.psm1'
Import-Module $flowTargetUtilsModule -Force

$resultUtilsModule = Join-Path $PSScriptRoot '..\..\utils\common\ResultUtils.psm1'
Import-Module $resultUtilsModule -Force

$targetScript = Join-Path $PSScriptRoot '.\scripts\Conclude-MonthFolder.ps1'
$targetScript = (Resolve-Path -LiteralPath $targetScript -ErrorAction Stop).Path

$target = Resolve-FlowTargetPath -RootPath $StoragePath -PathType $PathType -Subfolder $Subfolder -PromptLabel 'conclude month folder'
if ($target.Status -eq 'Aborted') {
    Write-Host 'Conclude month folder action aborted (ESC).' -ForegroundColor DarkYellow
    Write-Output (New-ToolResult -Status 'Aborted' -Data @{
            RootPath = $StoragePath
            PathType = $PathType
            Action = 'Conclude Month Folder'
        })
    exit 0
}

if ($target.UsedFallback) {
    Write-Host "Using latest month folder: $($target.SubfolderName)" -ForegroundColor Gray
}

& $targetScript -Path $StoragePath -PathType $PathType -TargetFolderName $target.SubfolderName
