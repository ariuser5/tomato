Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$commandUtilsModule = Join-Path $PSScriptRoot '..\..\..\..\utils\common\CommandUtils.psm1'
Import-Module $commandUtilsModule -Force

# Runs rclone with JSON output and parses the result.
# Params:
# - RcloneArguments: arguments passed to rclone.
# Returns: parsed JSON object/array, or empty array when no output.
function Get-RcloneJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$RcloneArguments
    )

    $raw = Invoke-Rclone -Arguments $RcloneArguments -ErrorMessage 'rclone JSON command failed.'
    if (-not $raw -or $raw.Count -eq 0) {
        return @()
    }

    return ($raw | ConvertFrom-Json)
}

# Builds a browser URL for a Drive item, with search fallback.
# Params:
# - RemoteItemPath: full remote item path used for id lookup.
# - FallbackQuery: text used in Drive search URL when id is unavailable.
# Returns: [string] URL that can be opened in a browser.
function Get-DriveBrowserUrl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RemoteItemPath,

        [Parameter(Mandatory = $true)]
        [string]$FallbackQuery
    )

    try {
        $stat = Get-RcloneJson -RcloneArguments @('lsjson', '--stat', '--original', $RemoteItemPath)

        $id = $null
        if ($null -ne $stat) {
            if ($stat.PSObject.Properties.Name -contains 'OrigID' -and $stat.OrigID) {
                $id = $stat.OrigID
            } elseif ($stat.PSObject.Properties.Name -contains 'ID' -and $stat.ID) {
                $id = $stat.ID
            }
        }

        if ($id) {
            return "https://drive.google.com/open?id=$id"
        }
    } catch {
        # Fall through to the search URL.
    }

    $encoded = [System.Uri]::EscapeDataString($FallbackQuery)
    return "https://drive.google.com/drive/search?q=$encoded"
}

Export-ModuleMember -Function Get-RcloneJson, Get-DriveBrowserUrl
