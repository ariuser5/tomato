Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Checks whether an executable can be resolved.
# Params:
# - Exe: executable name on PATH or absolute/relative file path.
# Returns: [bool] true when executable exists.
function Test-ExecutableAvailable {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Exe
    )

    if (-not $Exe) { return $false }

    if ($Exe -match '^[a-zA-Z]:\\' -or $Exe.Contains('\\') -or $Exe.Contains('/')) {
        return (Test-Path -LiteralPath $Exe -PathType Leaf)
    }

    return ($null -ne (Get-Command $Exe -ErrorAction SilentlyContinue))
}

# Verifies that rclone is available for remote operations.
# Params: none.
# Returns: nothing; throws when rclone is missing.
function Assert-RcloneAvailable {
    [CmdletBinding()]
    param()

    if (-not (Test-ExecutableAvailable -Exe 'rclone')) {
        throw "rclone not found on PATH. Install it (e.g., 'winget install Rclone.Rclone') and ensure it's available in your session."
    }
}

# Executes rclone with centralized error handling.
# Params:
# - Arguments: argument array passed to rclone.
# - ErrorMessage: optional custom prefix for thrown errors.
# Returns: [string[]] command output lines.
function Invoke-Rclone {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [Parameter()]
        [string]$ErrorMessage = 'rclone command failed.'
    )

    Assert-RcloneAvailable

    $output = & rclone @Arguments
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "$ErrorMessage Exit code: $exitCode. Command: rclone $($Arguments -join ' ')"
    }

    return @($output)
}

Export-ModuleMember -Function Test-ExecutableAvailable, Assert-RcloneAvailable, Invoke-Rclone
