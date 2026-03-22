Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-CategoryPathSegments {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object]$Entry)

    if (-not ($Entry.PSObject.Properties.Name -contains 'categoryPath')) {
        return @()
    }

    $value = $Entry.categoryPath
    if (-not ($value -is [array])) {
        return @()
    }

    return @(
        @($value) |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object { $_ }
    )
}

function Get-ManagedFlowAliases {
    [CmdletBinding()]
    param()

    return @(
        'Run Monthly Flow',
        'Preview Storage',
        'Create Monthly Report',
        'Label Files',
        'Archive By Label',
        'Create Draft Email',
        'Conclude Month Folder'
    )
}

Export-ModuleMember -Function Get-CategoryPathSegments, Get-ManagedFlowAliases
