<#
-------------------------------------------------------------------------------
Select-ViewOption.ps1
-------------------------------------------------------------------------------
Generic interactive view option selector.

Use this when you need to:
  - display a list of options/items,
  - prompt the user for a selection,
  - return the selected input to the caller.

The caller is responsible for interpreting the selected value and deciding what
action to execute.

Example:
  $items = @('Automations', 'Settings', 'Quit')

  $result = & "$env:TOMATO_ROOT/base/utils/Select-ViewOption.ps1" \
      -Items $items \
      -RenderStyle Numbered \
      -Prompt "Select any option in the menu, 'q' to quit, 'b' to go back."

  # Consumer decides what to do based on $result.Selection
-------------------------------------------------------------------------------
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string[]]$Items,

    [Parameter()]
    [ValidateSet('Numbered', 'Bulleted', 'Plain')]
    [string]$RenderStyle = 'Numbered',

    [Parameter()]
    [string]$Bullet = '-',

    [Parameter()]
    [string]$Prompt = 'Select',

    [Parameter()]
    [string]$Title,

    # Keep asking until a non-empty input is provided.
    [Parameter()]
    [bool]$LoopUntilNonEmpty = $true,

    # Trim selection before returning.
    [Parameter()]
    [switch]$TrimSelection
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $Items -or $Items.Count -eq 0) {
    throw 'Items cannot be empty.'
}

while ($true) {
    if ($Title) {
        Write-Host $Title -ForegroundColor Cyan
    }

    for ($i = 0; $i -lt $Items.Count; $i++) {
        $line = switch ($RenderStyle) {
            'Numbered' { "[{0}] {1}" -f ($i + 1), $Items[$i] }
            'Bulleted' { "{0} {1}" -f $Bullet, $Items[$i] }
            default { "$($Items[$i])" }
        }

        Write-Host $line -ForegroundColor Gray
    }

    Write-Host ''
    $rawSelection = Read-Host $Prompt
    $selection = [string]$rawSelection
    if ($TrimSelection) {
        $selection = ($selection ?? '').Trim()
    }

    if (-not $selection) {
        if ($LoopUntilNonEmpty) {
            Write-Host 'Please enter a value.' -ForegroundColor Yellow
            Write-Host ''
            continue
        }

        Write-Output ([pscustomobject]@{
                Status = 'NoInput'
                Selection = $selection
                Selected = $false
            })
        exit 0
    }

    Write-Output ([pscustomobject]@{
            Status = 'Selected'
            Selection = $selection
            Selected = $true
        })
    exit 0
}
