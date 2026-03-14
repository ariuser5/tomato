# -----------------------------------------------------------------------------
# Get-LastMonth.ps1
# -----------------------------------------------------------------------------
# Returns the latest month-pattern value from input values.
#
# Input format: optional underscore(s) + month + dash + year
#   [_]mon-YYYY
#
# Examples:
#   .\Get-LastMonth.ps1 -Values @("jan-2026", "_apr-2026")
#   .\Get-LastMonth.ps1 -Values @("jan-2026", "invalid", "_apr-2026") -SkipInvalid
# -----------------------------------------------------------------------------

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$Values,

    [Parameter()]
    [switch]$SkipInvalid
)

$monthUtilsModule = Join-Path $PSScriptRoot '.\modules\MonthUtils.psm1'
Import-Module $monthUtilsModule -Force

return (Get-LastMonthValue -Values $Values -SkipInvalid:$SkipInvalid)
