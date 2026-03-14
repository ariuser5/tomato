
# -----------------------------------------------------------------------------
# Ensure-NewMonthFolder.ps1
# -----------------------------------------------------------------------------
# Creates the next missing month folder (with prefix) in a directory.
# Supports both local filesystem paths and rclone remote specs.
#
# Usage:
#   .\Ensure-NewMonthFolder.ps1 -Path "gdrive:path/to/dir" [-PathType Auto|Local|Remote] [-StartYear 2025] [-NewFolderPrefix "_"]
#
# Parameters:
#   -Path              Base folder where month folders live (local path or rclone remote spec)
#   -PathType          Auto|Local|Remote (default: Auto)
#   -StartYear         Year to start searching for missing months (default: current year)
#   -NewFolderPrefix   Prefix for new folders (default: "_")
#
# Behavior:
#   - Scans the target directory for folders named "mon-YYYY" or "_mon-YYYY" (e.g., "jan-2025", "_jan-2025")
#   - Finds the latest existing month for each year, starting from StartYear
#   - If all months exist for a year, continues to the next year
#   - Creates the next missing month folder with the specified prefix
#   - Writes status to host/information streams
#   - Emits a single structured result object on the output stream
# -----------------------------------------------------------------------------
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter()]
    [ValidateSet('Auto', 'Local', 'Remote')]
    [string]$PathType = 'Auto',

    # Start year to check (default: current year)
    [int]$StartYear = (Get-Date).Year,

    # Prefix to use when creating a fresh folder (default: underscore)
    [string]$NewFolderPrefix = "_"
)

$ErrorActionPreference = "Stop"

$pathModule = Join-Path $PSScriptRoot '..\..\utils\PathUtils.psm1'
Import-Module $pathModule -Force

$monthUtilsModule = Join-Path $PSScriptRoot '.\modules\MonthUtils.psm1'
Import-Module $monthUtilsModule -Force

$commandUtilsModule = Join-Path $PSScriptRoot '..\..\utils\common\CommandUtils.psm1'
Import-Module $commandUtilsModule -Force

$resultUtilsModule = Join-Path $PSScriptRoot '..\..\utils\common\ResultUtils.psm1'
Import-Module $resultUtilsModule -Force

$baseInfo = $null
$baseInfo = Resolve-UnifiedPath -Path $Path -PathType $PathType

# Get list of existing directories
$existingDirs = @()
if ($baseInfo.PathType -eq 'Remote') {
    Assert-RcloneAvailable

    try {
        $existingDirs = @(Invoke-Rclone -Arguments @('lsf', $baseInfo.Normalized, '--dirs-only') -ErrorMessage "Failed to list remote directory '$($baseInfo.Normalized)'.")

        # rclone --dirs-only returns folder names with trailing '/'
        $existingDirs = @(
            $existingDirs |
                Where-Object { $_ -ne $null -and $_ -ne '' } |
                ForEach-Object { $_.TrimEnd('/') }
        )
    } catch {
        Write-Error "Failed to list remote directory '$($baseInfo.Normalized)'. Ensure rclone is configured and the path exists."
        exit 1
    }
} else {
    try {
        $existingDirs = @(Get-ChildItem -LiteralPath $baseInfo.LocalPath -Directory -ErrorAction Stop | Select-Object -ExpandProperty Name)
    } catch {
        Write-Error "Failed to list local directory '$($baseInfo.LocalPath)'. Ensure the path exists."
        exit 1
    }
}

$where = if ($baseInfo.PathType -eq 'Remote') { 'remote' } else { 'local' }
Write-Host "Scanning $where directory: $($baseInfo.Normalized)" -ForegroundColor Cyan

$nextFolder = Get-NextMissingMonthFolder -ExistingFolderNames $existingDirs -StartYear $StartYear -NewFolderPrefix $NewFolderPrefix
$newFolderName = $nextFolder.FolderName
$targetPath = Join-UnifiedPath -Base $baseInfo.Normalized -Child $newFolderName -PathType $baseInfo.PathType

Write-Host "Creating new folder: $newFolderName" -ForegroundColor Yellow

if ($baseInfo.PathType -eq 'Remote') {
    try {
        Invoke-Rclone -Arguments @('mkdir', $targetPath) -ErrorMessage "Failed to create folder '$newFolderName' at '$($baseInfo.Normalized)'." | Out-Null
    } catch {
        Write-Error "Failed to create folder '$newFolderName' at '$($baseInfo.Normalized)'."
        exit 2
    }
} else {
    try {
        New-Item -ItemType Directory -Path $targetPath -Force | Out-Null
    } catch {
        Write-Error "Failed to create folder '$newFolderName' at '$($baseInfo.LocalPath)'."
        exit 2
    }
}

Write-Host "✓ Created folder: $newFolderName" -ForegroundColor Green
Write-Host "  Path: $targetPath" -ForegroundColor Gray
Write-Output (New-ToolResult -Status 'Created' -Data @{
        Path = $targetPath
        FolderName = $newFolderName
    })
exit 0
