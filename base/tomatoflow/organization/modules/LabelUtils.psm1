Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Extracts a label token from a basename like "[LABEL] file.pdf".
# Params:
# - Basename: file basename to inspect.
# Returns: [string] label name, or $null when none exists.
function Get-LabelFromBasename {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Basename
    )

    if ($Basename -match '^\[([^\]]+)\]\s*') {
        return $Matches[1]
    }

    return $null
}

# Normalizes supported archive extension aliases.
# Params:
# - Extension: user-provided extension (with or without dot).
# Returns: [string] normalized extension (for example tar.gz).
function Convert-ArchiveExtension {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Extension
    )

    $e = $Extension.Trim()
    if ($e.StartsWith('.')) { $e = $e.TrimStart('.') }

    $e = $e.ToLowerInvariant()
    if ($e -eq 'targz') {
        return 'tar.gz'
    }

    return $e
}

# Builds file selector pattern for a given label.
# Params:
# - Label: label token to target.
# Returns: [string] selector pattern used by archive scripts.
function Get-LabelFileSelector {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    return "[$Label] *"
}

# Ensures a basename is unique by appending numeric suffixes.
# Params:
# - DesiredBasename: preferred target name.
# - ExistingNames: case-insensitive set of names already in use.
# Returns: [string] unique basename.
function Get-UniqueBasename {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DesiredBasename,

        [Parameter(Mandatory = $true)]
        [System.Collections.Generic.HashSet[string]]$ExistingNames
    )

    if (-not $ExistingNames.Contains($DesiredBasename)) {
        return $DesiredBasename
    }

    $ext = [System.IO.Path]::GetExtension($DesiredBasename)
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($DesiredBasename)

    for ($i = 2; $i -lt 10000; $i++) {
        $candidate = "$stem ($i)$ext"
        if (-not $ExistingNames.Contains($candidate)) {
            return $candidate
        }
    }

    throw "Unable to find a unique name for '$DesiredBasename'."
}

# Builds regex that matches configured bracket labels at file start.
# Params:
# - ResolvedLabels: allowed labels list.
# Returns: [regex] compiled regex, or $null when no labels provided.
function New-AllowedLabelsRegex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$ResolvedLabels
    )

    $escaped = $ResolvedLabels | ForEach-Object { [regex]::Escape($_) }
    if (-not $escaped -or $escaped.Count -eq 0) {
        return $null
    }

    $pattern = "^\[(?:$($escaped -join '|'))\]\s+"
    return [regex]::new($pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
}

Export-ModuleMember -Function Get-LabelFromBasename, Convert-ArchiveExtension, Get-LabelFileSelector, Get-UniqueBasename, New-AllowedLabelsRegex
