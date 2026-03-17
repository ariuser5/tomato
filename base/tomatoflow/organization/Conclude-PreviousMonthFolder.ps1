# -----------------------------------------------------------------------------
# Conclude-PreviousMonthFolder.ps1
# -----------------------------------------------------------------------------
# Concludes the previously open month folder by removing underscore prefix.
#
# Behavior:
#   - Detects month folders that start with underscore (for example _jan-2026).
#   - Keeps the newest underscored month as the current open month.
#   - Renames the second newest underscored month by removing leading underscores.
#   - Supports both local filesystem and rclone remote paths.
# -----------------------------------------------------------------------------
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter()]
    [ValidateSet('Auto', 'Local', 'Remote')]
    [string]$PathType = 'Auto'
)

$ErrorActionPreference = 'Stop'

$pathModule = Join-Path $PSScriptRoot '..\..\utils\PathUtils.psm1'
Import-Module $pathModule -Force

$monthUtilsModule = Join-Path $PSScriptRoot '.\modules\MonthUtils.psm1'
Import-Module $monthUtilsModule -Force

$commandUtilsModule = Join-Path $PSScriptRoot '..\..\utils\common\CommandUtils.psm1'
Import-Module $commandUtilsModule -Force

$resultUtilsModule = Join-Path $PSScriptRoot '..\..\utils\common\ResultUtils.psm1'
Import-Module $resultUtilsModule -Force

$baseInfo = Resolve-UnifiedPath -Path $Path -PathType $PathType

$existingDirs = @()
if ($baseInfo.PathType -eq 'Remote') {
    Assert-RcloneAvailable

    try {
        $existingDirs = @(Invoke-Rclone -Arguments @('lsf', $baseInfo.Normalized, '--dirs-only') -ErrorMessage "Failed to list remote directory '$($baseInfo.Normalized)'.")
        $existingDirs = @(
            $existingDirs |
                Where-Object { $_ -ne $null -and $_ -ne '' } |
                ForEach-Object { $_.TrimEnd('/') }
        )
    }
    catch {
        Write-Error "Failed to list remote directory '$($baseInfo.Normalized)'."
        exit 1
    }
}
else {
    try {
        $existingDirs = @(Get-ChildItem -LiteralPath $baseInfo.LocalPath -Directory -ErrorAction Stop | Select-Object -ExpandProperty Name)
    }
    catch {
        Write-Error "Failed to list local directory '$($baseInfo.LocalPath)'."
        exit 1
    }
}

$prefixed = @($existingDirs | Where-Object { $_ -match '^_+[a-z]{3}-\d{4}$' })
if (-not $prefixed -or $prefixed.Count -lt 2) {
    Write-Host 'No previous open month to conclude.' -ForegroundColor Yellow
    Write-Output (New-ToolResult -Status 'NoOp' -Message 'Not enough underscored month folders to conclude a previous month.' -Data @{
            Path = $baseInfo.Normalized
            OpenMonthCount = if ($prefixed) { $prefixed.Count } else { 0 }
        })
    exit 0
}

$monthItems = @(Get-MonthItems -Values $prefixed -SkipInvalid)
if (-not $monthItems -or $monthItems.Count -lt 2) {
    Write-Host 'No valid previous open month to conclude.' -ForegroundColor Yellow
    Write-Output (New-ToolResult -Status 'NoOp' -Message 'Could not determine previous month from underscored folders.' -Data @{
            Path = $baseInfo.Normalized
        })
    exit 0
}

$sorted = $monthItems | Sort-Object -Property @{ Expression = { $_.Year }; Descending = $true }, @{ Expression = { $_.Month }; Descending = $true }
$currentOpen = $sorted[0]
$previousOpen = $sorted[1]

$sourceName = $previousOpen.Value
$targetName = $sourceName -replace '^_+', ''

if (-not $targetName -or $targetName -eq $sourceName) {
    Write-Host 'Previous month folder already concluded.' -ForegroundColor Yellow
    Write-Output (New-ToolResult -Status 'NoOp' -Message 'Previous month folder does not need rename.' -Data @{
            Path = $baseInfo.Normalized
            SourceName = $sourceName
        })
    exit 0
}

$targetExists = $existingDirs -contains $targetName
if ($targetExists) {
    Write-Error "Cannot conclude month '$sourceName': target '$targetName' already exists."
    exit 2
}

$sourcePath = Join-UnifiedPath -Base $baseInfo.Normalized -Child $sourceName -PathType $baseInfo.PathType
$targetPath = Join-UnifiedPath -Base $baseInfo.Normalized -Child $targetName -PathType $baseInfo.PathType

Write-Host "Current open month stays: $($currentOpen.Value)" -ForegroundColor Gray
Write-Host "Concluding previous month: $sourceName -> $targetName" -ForegroundColor Cyan

if ($baseInfo.PathType -eq 'Remote') {
    try {
        Invoke-Rclone -Arguments @('moveto', $sourcePath, $targetPath) -ErrorMessage "Failed to rename '$sourceName' to '$targetName'." | Out-Null
    }
    catch {
        Write-Error "Failed to rename '$sourceName' to '$targetName'."
        exit 2
    }
}
else {
    try {
        Rename-Item -LiteralPath $sourcePath -NewName $targetName -ErrorAction Stop
    }
    catch {
        Write-Error "Failed to rename '$sourceName' to '$targetName'."
        exit 2
    }
}

Write-Host "✓ Concluded folder: $targetName" -ForegroundColor Green
Write-Output (New-ToolResult -Status 'Concluded' -Data @{
        Path = $baseInfo.Normalized
        ConcludedFrom = $sourceName
        ConcludedTo = $targetName
        CurrentOpen = $currentOpen.Value
    })

exit 0
