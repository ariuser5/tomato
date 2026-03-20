<#
-------------------------------------------------------------------------------
Ensure-NewMonthFolder.ps1
-------------------------------------------------------------------------------
Tomatoflow wrapper for ./scripts/Ensure-NewMonthFolder.ps1.

Behavior:
- If -StoragePath is not provided, asks the user to enter it interactively.
- If the user presses Enter with no value, defaults to the current user profile path.
- Forwards supported parameters to the underlying script.
-------------------------------------------------------------------------------
#>

[CmdletBinding()]
param(
    [Parameter()]
    [Alias('Path')]
    [string]$StoragePath,

    [Parameter()]
    [ValidateSet('Auto', 'Local', 'Remote')]
    [string]$PathType = 'Auto',

    [Parameter()]
    [int]$StartYear = (Get-Date).Year,

    [Parameter()]
    [string]$NewFolderPrefix = '_'
)

$ErrorActionPreference = 'Stop'

function Get-DefaultUserProfilePath {
    [CmdletBinding()]
    param()

    $userProfile = ''
    try {
        $userProfile = [Environment]::GetFolderPath('UserProfile')
    } catch {
        $userProfile = ''
    }

    if (-not $userProfile) {
        $userProfile = ([string]$env:HOME ?? '').Trim()
    }

    if (-not $userProfile) {
        $userProfile = ([string]$env:USERPROFILE ?? '').Trim()
    }

    if (-not $userProfile) {
        throw 'Could not determine a default user profile path for this OS.'
    }

    return $userProfile
}

function Resolve-TargetPath {
    [CmdletBinding()]
    param([Parameter()][string]$InitialPath)

    $resolved = ([string]$InitialPath ?? '').Trim()
    if ($resolved) {
        return $resolved
    }

    $defaultPath = Get-DefaultUserProfilePath

    if (-not $Host.UI -or -not $Host.UI.RawUI) {
        return $defaultPath
    }

    $inputValue = Read-Host "Storage path was not provided. Enter -StoragePath value (Enter for default: $defaultPath)"
    $resolved = ([string]$inputValue ?? '').Trim()
    if (-not $resolved) {
        $resolved = $defaultPath
    }

    return $resolved
}

$targetScript = Join-Path $PSScriptRoot '.\scripts\Ensure-NewMonthFolder.ps1'
$targetScript = (Resolve-Path -LiteralPath $targetScript -ErrorAction Stop).Path

$resolvedPath = Resolve-TargetPath -InitialPath $StoragePath

$targetArgs = @{
    Path            = $resolvedPath
    PathType        = $PathType
    StartYear       = $StartYear
    NewFolderPrefix = $NewFolderPrefix
}

& $targetScript @targetArgs
