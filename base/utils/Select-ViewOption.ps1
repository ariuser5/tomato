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

ESC behavior is configurable via -EscBehavior:
    - ClearInput: clear current prompt text and keep reading.
    - ExitView: return Status='Escaped'.
    - GoBack: return Status='GoBack'.

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
    [switch]$TrimSelection,

    [Parameter()]
    [ValidateSet('ClearInput', 'ExitView', 'GoBack')]
    [string]$EscBehavior = 'ExitView'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not $Items -or $Items.Count -eq 0) {
    throw 'Items cannot be empty.'
}

function New-SelectionResult {
    param(
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter()][string]$Selection = '',
        [Parameter()][bool]$Selected = $false
    )

    return [pscustomobject]@{
        Status = $Status
        Selection = $Selection
        Selected = $Selected
    }
}

function Read-SelectionRaw {
    param(
        [Parameter(Mandatory = $true)][string]$PromptText,
        [Parameter(Mandatory = $true)][string]$EscMode
    )

    # Fallback host: cannot detect ESC key directly.
    if (-not $Host.UI -or -not $Host.UI.RawUI) {
        $fallback = Read-Host $PromptText
        return [pscustomobject]@{
            Status = 'SelectedFallback'
            Value = [string]$fallback
        }
    }

    Write-Host ("{0}: " -f $PromptText) -NoNewline
    $buffer = New-Object System.Text.StringBuilder

    while ($true) {
        $keyInfo = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
        $virtualKey = if ($keyInfo.PSObject.Properties.Match('VirtualKeyCode').Count -gt 0) {
            [int]$keyInfo.VirtualKeyCode
        }
        elseif ($keyInfo.PSObject.Properties.Match('Key').Count -gt 0) {
            [int]$keyInfo.Key
        }
        else {
            -1
        }

        if ($virtualKey -eq [int][ConsoleKey]::Escape) {
            switch ($EscMode) {
                'ClearInput' {
                    while ($buffer.Length -gt 0) {
                        $null = $buffer.Remove($buffer.Length - 1, 1)
                        Write-Host "`b `b" -NoNewline
                    }
                    continue
                }
                'GoBack' {
                    Write-Host ''
                    return [pscustomobject]@{ Status = 'GoBack'; Value = '' }
                }
                default {
                    Write-Host ''
                    return [pscustomobject]@{ Status = 'Escaped'; Value = '' }
                }
            }
        }

        if ($virtualKey -eq [int][ConsoleKey]::Enter) {
            Write-Host ''
            return [pscustomobject]@{ Status = 'Submitted'; Value = $buffer.ToString() }
        }

        if ($virtualKey -eq [int][ConsoleKey]::Backspace) {
            if ($buffer.Length -gt 0) {
                $null = $buffer.Remove($buffer.Length - 1, 1)
                Write-Host "`b `b" -NoNewline
            }
            continue
        }

        $ch = $keyInfo.Character
        if ($ch -and -not [char]::IsControl($ch)) {
            $null = $buffer.Append($ch)
            Write-Host $ch -NoNewline
        }
    }
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
    $rawResult = Read-SelectionRaw -PromptText $Prompt -EscMode $EscBehavior
    if ($rawResult.Status -eq 'Escaped') {
        Write-Output (New-SelectionResult -Status 'Escaped' -Selected:$false)
        exit 0
    }
    if ($rawResult.Status -eq 'GoBack') {
        Write-Output (New-SelectionResult -Status 'GoBack' -Selection 'b' -Selected:$false)
        exit 0
    }

    $selection = [string]$rawResult.Value
    if ($TrimSelection) {
        $selection = ($selection ?? '').Trim()
    }

    if (-not $selection) {
        if ($LoopUntilNonEmpty) {
            Write-Host 'Please enter a value.' -ForegroundColor Yellow
            Write-Host ''
            continue
        }

        Write-Output (New-SelectionResult -Status 'NoInput' -Selection $selection -Selected:$false)
        exit 0
    }

    $status = if ($rawResult.Status -eq 'SelectedFallback') { 'SelectedFallback' } else { 'Selected' }
    Write-Output (New-SelectionResult -Status $status -Selection $selection -Selected:$true)
    exit 0
}
