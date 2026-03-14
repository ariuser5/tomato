Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$monthUtilsModule = Join-Path $PSScriptRoot '.\modules\MonthUtils.psm1'
Import-Module $monthUtilsModule -Force

Export-ModuleMember -Variable MonthNames, MonthPattern
