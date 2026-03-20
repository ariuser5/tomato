<#
-------------------------------------------------------------------------------
TodoEditorUtils.psm1
-------------------------------------------------------------------------------
Shared parsing and error-header helpers for git-rebase-like editor todo files.

Exported functions:
  - Read-StructuredTodo
  - Write-TodoErrorHeader
-------------------------------------------------------------------------------
#>

function Read-StructuredTodo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TodoPath,

        [Parameter()]
        [string]$ExpectedUsage = '<action> <item>',

        [Parameter()]
        [string]$NameLabel = 'item',

        [Parameter()]
        [switch]$LowercaseAction,

        [Parameter()]
        [ValidateSet('apply', 'reset')]
        [string]$EmptyMode = 'reset'
    )

    $lines = Get-Content -LiteralPath $TodoPath -ErrorAction Stop
    $ops = New-Object System.Collections.Generic.List[object]

    foreach ($raw in $lines) {
        $line = ([string]$raw ?? '').Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }

        if ($line -ieq 'abort') {
            return [pscustomobject]@{ Mode = 'abort' }
        }

        if ($line -ieq 'reset') {
            return [pscustomobject]@{ Mode = 'reset' }
        }

        if ($line -notmatch '^(?<action>\S+)\s+(?<name>.+)$') {
            throw "Invalid todo line: '$line' (expected: $ExpectedUsage)"
        }

        $action = $Matches['action'].Trim()
        if ($LowercaseAction.IsPresent) {
            $action = $action.ToLowerInvariant()
        }

        $nameRaw = $Matches['name'].Trim()
        if (-not $nameRaw) {
            throw "Invalid todo line: '$line' (missing $NameLabel)"
        }

        $name = $null
        if ($nameRaw.StartsWith('"')) {
            if ($nameRaw -notmatch '^"(?<inner>(?:\\.|[^"\\])*)"\s*$') {
                throw "Invalid quoted $NameLabel in todo line: '$line'"
            }

            $inner = $Matches['inner']
            $sbName = New-Object System.Text.StringBuilder
            for ($i = 0; $i -lt $inner.Length; $i++) {
                $ch = $inner[$i]
                if ($ch -eq '\\') {
                    if ($i + 1 -ge $inner.Length) { throw "Invalid escape sequence in todo line: '$line'" }
                    $next = $inner[$i + 1]
                    switch ($next) {
                        '"' { $null = $sbName.Append('"') }
                        '\\' { $null = $sbName.Append('\\') }
                        default { $null = $sbName.Append($next) }
                    }
                    $i++
                    continue
                }
                $null = $sbName.Append($ch)
            }
            $name = $sbName.ToString()
        }
        else {
            $name = $nameRaw
        }

        if (-not $name) {
            throw "Invalid todo line: '$line' (missing $NameLabel)"
        }

        $ops.Add([pscustomobject]@{ Action = $action; Name = $name }) | Out-Null
    }

    if ($ops.Count -eq 0 -and $EmptyMode -eq 'reset') {
        return [pscustomobject]@{ Mode = 'reset' }
    }

    return [pscustomobject]@{ Mode = 'apply'; Ops = @($ops.ToArray()) }
}

function Write-TodoErrorHeader {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TodoPath,

        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage
    )

    $lines = Get-Content -LiteralPath $TodoPath -ErrorAction Stop

    $begin = '# ERROR-BEGIN'
    $end = '# ERROR-END'

    $beginIndex = -1
    $endIndex = -1
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($beginIndex -lt 0 -and $lines[$i].Trim() -eq $begin) { $beginIndex = $i; continue }
        if ($beginIndex -ge 0 -and $lines[$i].Trim() -eq $end) { $endIndex = $i; break }
    }

    if ($beginIndex -ge 0 -and $endIndex -ge $beginIndex) {
        if ($beginIndex -eq 0) {
            $lines = $lines[($endIndex + 1)..($lines.Count - 1)]
        }
        else {
            $before = $lines[0..($beginIndex - 1)]
            $after = if ($endIndex + 1 -le ($lines.Count - 1)) { $lines[($endIndex + 1)..($lines.Count - 1)] } else { @() }
            $lines = @($before + $after)
        }
    }

    $header = @(
        $begin,
        "# ERROR: $ErrorMessage",
        '# Fix the todo and save+close to continue.',
        $end,
        '#'
    )

    Set-Content -LiteralPath $TodoPath -Value ($header + $lines) -Encoding UTF8
}

Export-ModuleMember -Function Read-StructuredTodo, Write-TodoErrorHeader
