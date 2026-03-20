Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Convert-PathPatternToRegex {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Pattern
    )

    $raw = ([string]$Pattern ?? '').Trim()
    if (-not $raw) {
        throw 'Pattern cannot be empty.'
    }

    $normalized = $raw.Replace('\\', '/')
    $anchored = $normalized.StartsWith('/')
    if ($anchored) {
        $normalized = $normalized.Substring(1)
    }

    $directoryOnly = $normalized.EndsWith('/')
    if ($directoryOnly) {
        $normalized = $normalized.TrimEnd('/')
    }

    if (-not $normalized) {
        throw "Pattern '$Pattern' resolves to an empty expression."
    }

    $hasSlash = $normalized.Contains('/')

    $sb = New-Object System.Text.StringBuilder
    $inClass = $false
    $i = 0

    while ($i -lt $normalized.Length) {
        $ch = $normalized[$i]

        if ($ch -eq '[') {
            $inClass = $true
            $null = $sb.Append('[')
            $i++
            continue
        }

        if ($ch -eq ']' -and $inClass) {
            $inClass = $false
            $null = $sb.Append(']')
            $i++
            continue
        }

        if ($inClass) {
            $null = $sb.Append($ch)
            $i++
            continue
        }

        if ($ch -eq '*') {
            if ($i + 1 -lt $normalized.Length -and $normalized[$i + 1] -eq '*') {
                $null = $sb.Append('.*')
                $i += 2
                continue
            }

            $null = $sb.Append('[^/]*')
            $i++
            continue
        }

        if ($ch -eq '?') {
            $null = $sb.Append('[^/]')
            $i++
            continue
        }

        if ($ch -eq '/') {
            $null = $sb.Append('/')
            $i++
            continue
        }

        $null = $sb.Append([regex]::Escape([string]$ch))
        $i++
    }

    $core = $sb.ToString()

    if (-not $hasSlash) {
        if ($directoryOnly) {
            return "(?:^|.*/){0}(?:/.*)?$" -f $core
        }

        return "(?:^|.*/){0}$" -f $core
    }

    if ($anchored) {
        if ($directoryOnly) {
            return "^{0}(?:/.*)?$" -f $core
        }

        return "^{0}$" -f $core
    }

    if ($directoryOnly) {
        return "^(?:.*/)?{0}(?:/.*)?$" -f $core
    }

    return "^(?:.*/)?{0}$" -f $core
}

function Select-PathsByPattern {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Paths,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$IncludePatterns,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$ExcludePatterns = @()
    )

    $include = @($IncludePatterns | ForEach-Object { ([string]$_ ?? '').Trim() } | Where-Object { $_ })
    $exclude = @($ExcludePatterns | ForEach-Object { ([string]$_ ?? '').Trim() } | Where-Object { $_ })

    if (-not $include -or $include.Count -eq 0) {
        return @()
    }

    $includeRegexes = @($include | ForEach-Object { [regex](Convert-PathPatternToRegex -Pattern $_) })
    $excludeRegexes = @($exclude | ForEach-Object { [regex](Convert-PathPatternToRegex -Pattern $_) })

    $result = @()
    foreach ($inputPath in @($Paths)) {
        if ($null -eq $inputPath) { continue }

        $candidate = ([string]$inputPath).Trim().Replace('\', '/').TrimStart('/')
        if (-not $candidate) { continue }

        $isIncluded = $false
        foreach ($rx in $includeRegexes) {
            if ($rx.IsMatch($candidate)) {
                $isIncluded = $true
                break
            }
        }
		
        if (-not $isIncluded) { continue }

        $isExcluded = $false
        foreach ($rx in $excludeRegexes) {
            if ($rx.IsMatch($candidate)) {
                $isExcluded = $true
                break
            }
        }
        if ($isExcluded) { continue }

        $result += $inputPath
    }

    return @($result)
}

Export-ModuleMember -Function Convert-PathPatternToRegex, Select-PathsByPattern
