<#
-------------------------------------------------------------------------------
Create-MonthlyReport.ps1
-------------------------------------------------------------------------------
Orchestrates the creation of a new monthly report folder on Google Drive and copies template files into it.

Usage:
    .\Create-MonthlyReport.ps1 -Path "gdrive:path/to/dir" [-PathType Auto|Local|Remote] [-StartYear 2025] [-NewFolderPrefix "_"] [-ArtifactsSourcePath "C:\template\dir"]

Parameters:
    -Path              Base folder where month folders live (local path or rclone remote spec)
    -PathType          Auto|Local|Remote (default: Auto)
    -StartYear         Year to start searching for missing months (default: current year)
    -NewFolderPrefix   Prefix for new folders (default: "_")
    -ArtifactsSourcePath Optional source folder to copy artifacts from (local or remote). If omitted, copy step is skipped.

Behavior:
    - Calls Ensure-NewMonthFolder.ps1 to create the next missing month folder (with prefix)
    - If a folder is created and -ArtifactsSourcePath is set, calls Copy-ToMonthFolder.ps1 to copy artifacts into it
    - If -ArtifactsSourcePath is not set, month folder is created without copying artifacts
    - Prints progress and summary output
-------------------------------------------------------------------------------
#>
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
    [string]$NewFolderPrefix = "_",

    # Optional source folder to copy artifacts from.
    [string]$ArtifactsSourcePath = ''
)

$ErrorActionPreference = "Stop"

# Paths
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ensureScriptPath = Join-Path $scriptDir ".\Ensure-NewMonthFolder.ps1"
$copyScriptPath = Join-Path $scriptDir ".\Copy-ToMonthFolder.ps1"

$pathModule = Join-Path $scriptDir "..\..\..\utils\PathUtils.psm1"
Import-Module $pathModule -Force

$resultUtilsModule = Join-Path $scriptDir "..\..\..\utils\common\ResultUtils.psm1"
Import-Module $resultUtilsModule -Force

$baseInfo = Resolve-UnifiedPath -Path $Path -PathType $PathType

# Validate scripts exist
if (-not (Test-Path $ensureScriptPath)) {
    Write-Error "Ensure-NewMonthFolder.ps1 not found at: $ensureScriptPath"
    exit 1
}

if (-not (Test-Path $copyScriptPath)) {
    Write-Error "Copy-ToMonthFolder.ps1 not found at: $copyScriptPath"
    exit 1
}

$resolvedArtifactsSourcePath = ([string]$ArtifactsSourcePath ?? '').Trim()

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Creating New Monthly Report" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Ensure month folder exists
Write-Host "[1/2] Creating month folder..." -ForegroundColor Yellow
try {
    $ensureOutput = & $ensureScriptPath `
        -Path $baseInfo.Normalized `
        -PathType $baseInfo.PathType `
        -StartYear $StartYear `
        -NewFolderPrefix $NewFolderPrefix
    
    $exitCode = $LASTEXITCODE
} catch {
    Write-Error "Failed to run Ensure-NewMonthFolder.ps1: $_"
    exit 1
}

# Parse output (structured object preferred; legacy string supported)
$createdPath = $null
foreach ($item in @($ensureOutput)) {
    if ($item -is [pscustomobject]) {
        if ($item.PSObject.Properties.Match('Status').Count -gt 0 -and
            $item.PSObject.Properties.Match('Path').Count -gt 0 -and
            "$($item.Status)" -eq 'Created') {
            $createdPath = "$($item.Path)"
            break
        }
        continue
    }

    if ("$item" -match '^CREATED:(.+)$') {
        $createdPath = $Matches[1]
        break
    }
}

if ($exitCode -ne 0 -or $null -eq $createdPath) {
    Write-Host ""
    Write-Host "No new folder was created. Output from Ensure-NewMonthFolder.ps1:" -ForegroundColor Yellow
    $ensureOutput | ForEach-Object { Write-Host "  $_" -ForegroundColor Gray }
    Write-Host ""
    Write-Host "Exiting without copying files." -ForegroundColor Yellow
    exit 0
}

Write-Host "      ✓ Folder created: $createdPath" -ForegroundColor Green
Write-Host ""

# Step 2: Optionally copy artifacts to the new folder
if ($resolvedArtifactsSourcePath) {
    Write-Host "[2/2] Copying artifacts to new folder..." -ForegroundColor Yellow
    try {
        $null = & $copyScriptPath `
            -SourcePath $resolvedArtifactsSourcePath `
            -DestinationPath $createdPath

        if ($LASTEXITCODE -ne 0) {
            Write-Error "Copy-ToMonthFolder.ps1 failed with exit code $LASTEXITCODE"
            exit 2
        }
    }
    catch {
        Write-Error "Failed to run Copy-ToMonthFolder.ps1: $_"
        exit 2
    }
}
else {
    Write-Host "[2/2] Skipped artifact copy: -ArtifactsSourcePath not provided." -ForegroundColor DarkYellow
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "✓ Monthly Report Initialized" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "Location: $createdPath" -ForegroundColor Gray
Write-Host ""

Write-Output (New-ToolResult -Status 'Initialized' -Data @{
        Path = $createdPath
    ArtifactsCopied = [bool]$resolvedArtifactsSourcePath
    ArtifactsSourcePath = $resolvedArtifactsSourcePath
    })

exit 0
