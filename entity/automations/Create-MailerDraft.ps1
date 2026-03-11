[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$InputJsonPath
)

$ErrorActionPreference = 'Stop'

function Resolve-ConfigPath {
    param([string]$PathValue)

    if (-not [string]::IsNullOrWhiteSpace($PathValue)) {
        return $PathValue
    }

    return Read-Host 'Path to mail draft JSON config (or q to abort)'
}

function Get-PathCandidates {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PathValue,
        [Parameter(Mandatory = $true)]
        [string[]]$BaseDirectories
    )

    $candidates = @()

    if ([System.IO.Path]::IsPathRooted($PathValue)) {
        $candidates += $PathValue
    } else {
        foreach ($baseDir in $BaseDirectories) {
            if (-not [string]::IsNullOrWhiteSpace($baseDir)) {
                $candidates += (Join-Path -Path $baseDir -ChildPath $PathValue)
            }
        }

        # Keep raw value as a final fallback for the current location/provider.
        $candidates += $PathValue
    }

    return @($candidates | Select-Object -Unique)
}

function Resolve-ExistingFilePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PathValue,
        [Parameter(Mandatory = $true)]
        [string[]]$BaseDirectories,
        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    $candidates = Get-PathCandidates -PathValue $PathValue -BaseDirectories $BaseDirectories
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            return (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path
        }
    }

    throw "$Label file not found: $PathValue"
}

Write-Host 'Starting Mailer Draft automation...' -ForegroundColor Cyan

$configPathInput = Resolve-ConfigPath -PathValue $InputJsonPath
if ([string]::IsNullOrWhiteSpace($configPathInput) -or $configPathInput -eq 'q') {
    Write-Host 'Aborted.' -ForegroundColor Yellow
    exit 0
}

$bootstrapBases = @(
    (Get-Location).Path,
    $env:APP_DIR,
    $env:TOMATO_ROOT
)

$configPath = Resolve-ExistingFilePath -PathValue $configPathInput -BaseDirectories $bootstrapBases -Label 'Config'

Write-Host "Using config path: $configPath" -ForegroundColor Gray

$mailerArgs = @('draft', '--param-file', $configPath)

Write-Host "Using config: $configPath" -ForegroundColor Gray
Write-Host "Running: mailer $($mailerArgs -join ' ')" -ForegroundColor Gray

try {
    & mailer @mailerArgs
    $exitCode = $LASTEXITCODE
    if ($null -eq $exitCode) { $exitCode = 0 }
    if ($exitCode -ne 0) {
        throw "mailer exited with code $exitCode"
    }
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

Write-Host 'Draft command completed.' -ForegroundColor Green
exit 0
