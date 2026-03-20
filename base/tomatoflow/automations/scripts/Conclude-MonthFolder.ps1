# -----------------------------------------------------------------------------
# Conclude-MonthFolder.ps1
# -----------------------------------------------------------------------------
# Concludes the last worked month folder by removing underscore prefix.
#
# Behavior:
#   - Detects month folders that start with underscore (for example _jan-2026).
#   - By default, picks the newest underscored month and concludes it.
#   - If -TargetFolderName is provided, concludes that specific folder.
#   - Supports both local filesystem and rclone remote paths.
# -----------------------------------------------------------------------------
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter()]
    [ValidateSet('Auto', 'Local', 'Remote')]
    [string]$PathType = 'Auto',

    [Parameter()]
    [string]$TargetFolderName
)

$ErrorActionPreference = 'Stop'

$pathModule = Join-Path $PSScriptRoot '..\..\..\utils\PathUtils.psm1'
Import-Module $pathModule -Force

$monthUtilsModule = Join-Path $PSScriptRoot '.\modules\MonthUtils.psm1'
Import-Module $monthUtilsModule -Force

$commandUtilsModule = Join-Path $PSScriptRoot '..\..\..\utils\common\CommandUtils.psm1'
Import-Module $commandUtilsModule -Force

$resultUtilsModule = Join-Path $PSScriptRoot '..\..\..\utils\common\ResultUtils.psm1'
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

$explicitTarget = ([string]$TargetFolderName ?? '').Trim()
$sourceName = ''

if ($explicitTarget) {
    $sourceName = $explicitTarget
}
else {
    $prefixed = @($existingDirs | Where-Object { $_ -match '^_+[a-z]{3}-\d{4}$' })
    if (-not $prefixed -or $prefixed.Count -lt 1) {
        Write-Host 'No open month to conclude.' -ForegroundColor Yellow
        Write-Output (New-ToolResult -Status 'NoOp' -Message 'No underscored month folders found to conclude.' -Data @{
                Path = $baseInfo.Normalized
                OpenMonthCount = if ($prefixed) { $prefixed.Count } else { 0 }
            })
        exit 0
    }

    $latestPrefixed = Get-LastMonthValue -Values $prefixed -SkipInvalid
    if (-not $latestPrefixed) {
        Write-Host 'No valid open month to conclude.' -ForegroundColor Yellow
        Write-Output (New-ToolResult -Status 'NoOp' -Message 'Could not determine last month from underscored folders.' -Data @{
                Path = $baseInfo.Normalized
            })
        exit 0
    }

    $sourceName = $latestPrefixed
}

if (-not ($existingDirs -contains $sourceName)) {
    Write-Error "Cannot conclude month '$sourceName': folder not found under '$($baseInfo.Normalized)'."
    exit 2
}

$targetName = $sourceName -replace '^_+', ''

if (-not $targetName -or $targetName -eq $sourceName) {
    Write-Host 'Month folder is already concluded.' -ForegroundColor Yellow
    Write-Output (New-ToolResult -Status 'NoOp' -Message 'Month folder does not need rename.' -Data @{
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

Write-Host "Concluding month folder: $sourceName -> $targetName" -ForegroundColor Cyan

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
        TargetFolderName = $sourceName
    })

exit 0
