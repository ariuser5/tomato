Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$MonthNames = @('jan', 'feb', 'mar', 'apr', 'may', 'jun', 'jul', 'aug', 'sep', 'oct', 'nov', 'dec')
$MonthPattern = '^(_*)([a-z]{3})-(\d{4})$'

# Parses month-tagged folder values into sortable objects.
# Params:
# - Values: raw names (for example _jan-2026).
# - SkipInvalid: ignore invalid entries instead of throwing.
# Returns: [pscustomobject[]] parsed month items.
function Get-MonthItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Values,

        [Parameter()]
        [switch]$SkipInvalid
    )

    $monthItems = @()
    foreach ($value in $Values) {
        $cleanValue = ($value ?? '').ToString().TrimEnd('/')

        if ($cleanValue -match $MonthPattern) {
            $prefix = $matches[1]
            $monthName = $matches[2]
            $year = [int]$matches[3]

            $monthIdx = $MonthNames.IndexOf($monthName.ToLower())
            if ($monthIdx -ge 0) {
                $monthItems += [pscustomobject]@{
                    Value  = $cleanValue
                    Year   = $year
                    Month  = $monthIdx
                    Prefix = $prefix
                }
            } elseif (-not $SkipInvalid) {
                throw "Invalid month name in value '$cleanValue'. Expected format: [_]mon-YYYY where mon is jan-dec."
            }
        } elseif (-not $SkipInvalid) {
            throw "Invalid format: '$cleanValue'. Expected format: [_]mon-YYYY (e.g., 'jan-2026', '_apr-2026')."
        }
    }

    return @($monthItems)
}

# Returns latest month-tagged value from input list.
# Params:
# - Values: month-tagged names.
# - SkipInvalid: ignore invalid entries instead of throwing.
# Returns: [string] latest value, or $null when none match.
function Get-LastMonthValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Values,

        [Parameter()]
        [switch]$SkipInvalid
    )

    $monthItems = Get-MonthItems -Values $Values -SkipInvalid:$SkipInvalid
    if (-not $monthItems -or $monthItems.Count -eq 0) {
        return $null
    }

    $sorted = $monthItems | Sort-Object -Property @{ Expression = { $_.Year }; Descending = $true }, @{ Expression = { $_.Month }; Descending = $true }
    return $sorted[0].Value
}

# Computes next missing month folder name starting from a year.
# Params:
# - ExistingFolderNames: existing month folder names.
# - StartYear: first year to evaluate.
# - NewFolderPrefix: prefix to prepend to generated folder name.
# Returns: [pscustomobject] Year, FolderName, and MissingTag.
function Get-NextMissingMonthFolder {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$ExistingFolderNames,

        [Parameter(Mandatory = $true)]
        [int]$StartYear,

        [Parameter()]
        [string]$NewFolderPrefix = '_'
    )

    $currentYear = $StartYear
    while ($true) {
        $yearDirs = @($ExistingFolderNames | Where-Object { $_ -match "^_*[a-z]{3}-$currentYear$" })

        $latestMonth = if ($yearDirs.Count -gt 0) {
            Get-LastMonthValue -Values $yearDirs -SkipInvalid
        } else {
            $null
        }

        $latestIdx = -1
        if ($latestMonth -and $latestMonth -match '^_*([a-z]{3})-\d{4}$') {
            $monthName = $matches[1]
            $latestIdx = $MonthNames.IndexOf($monthName.ToLower())
        }

        if ($latestIdx -eq ($MonthNames.Count - 1)) {
            $currentYear++
            continue
        }

        $nextIdx = $latestIdx + 1
        if ($nextIdx -ge $MonthNames.Count) {
            $currentYear++
            continue
        }

        $missing = "$($MonthNames[$nextIdx])-$currentYear"
        $newFolderName = "$NewFolderPrefix$missing"

        return [pscustomobject]@{
            Year       = $currentYear
            FolderName = $newFolderName
            MissingTag = $missing
        }
    }
}

Export-ModuleMember -Variable MonthNames, MonthPattern
Export-ModuleMember -Function Get-MonthItems, Get-LastMonthValue, Get-NextMissingMonthFolder
