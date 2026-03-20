<#
-------------------------------------------------------------------------------
Preview-Location.ps1
-------------------------------------------------------------------------------
Tomatoflow wrapper for base/utils/Preview-Location.ps1.

Behavior:
- If -StoragePath is not provided, asks the user to enter it interactively.
- If the user presses Enter without a value, defaults to the current user profile path.
- Forwards supported parameters to the underlying preview script.
-------------------------------------------------------------------------------
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('auto', 'filesystem', 'rclone')]
    [string]$Navigator = 'auto',

    [Parameter()]
    [Alias('Path')]
    [string]$StoragePath,

    [Parameter()]
    [int]$MaxDepth = 0,

    [Parameter()]
    [string]$Title = 'Preview'
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

function Resolve-PreviewRoot {
    [CmdletBinding()]
    param([Parameter()][string]$InitialRoot)

    $resolved = ([string]$InitialRoot ?? '').Trim()
    if ($resolved) {
        return $resolved
    }

    $defaultRoot = Get-DefaultUserProfilePath

    if (-not $Host.UI -or -not $Host.UI.RawUI) {
        return $defaultRoot
    }

    while (-not $resolved) {
        $inputValue = Read-Host "Storage path was not provided. Enter -StoragePath value (Enter for default: $defaultRoot)"
        $resolved = ([string]$inputValue ?? '').Trim()
        if (-not $resolved) {
            $resolved = $defaultRoot
        }
    }

    return $resolved
}

$previewScript = Join-Path $PSScriptRoot '..\..\utils\Preview-Location.ps1'
$previewScript = (Resolve-Path -LiteralPath $previewScript -ErrorAction Stop).Path

$resolvedRoot = Resolve-PreviewRoot -InitialRoot $StoragePath

$previewArgs = @{
    Navigator = $Navigator
    Root      = $resolvedRoot
    MaxDepth  = $MaxDepth
    Title     = $Title
}

& $previewScript @previewArgs
