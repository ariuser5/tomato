Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-TomatoRootPath {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$InputPath,

        [Parameter()]
        [switch]$ResolveRelative,

        [Parameter()]
        [string]$BasePath
    )

    $raw = ([string]$InputPath ?? '').Trim()
    if (-not $raw) {
        return ''
    }

    $tomatoRoot = ([string]$env:TOMATO_ROOT ?? '').Trim()
    $expanded = $raw

    if ($tomatoRoot) {
        if ($expanded -like '$env:TOMATO_ROOT') {
            $expanded = $tomatoRoot
        }
        elseif ($expanded -like '$TOMATO_ROOT') {
            $expanded = $tomatoRoot
        }
        elseif ($expanded -like '%TOMATO_ROOT%') {
            $expanded = $tomatoRoot
        }
        elseif ($expanded -like '$env:TOMATO_ROOT/*' -or $expanded -like '$env:TOMATO_ROOT\*') {
            $suffix = $expanded.Substring('$env:TOMATO_ROOT'.Length).TrimStart('/', [char]'\')
            $expanded = Join-Path $tomatoRoot $suffix
        }
        elseif ($expanded -like '$TOMATO_ROOT/*' -or $expanded -like '$TOMATO_ROOT\*') {
            $suffix = $expanded.Substring('$TOMATO_ROOT'.Length).TrimStart('/', [char]'\')
            $expanded = Join-Path $tomatoRoot $suffix
        }
        elseif ($expanded -like '%TOMATO_ROOT%/*' -or $expanded -like '%TOMATO_ROOT%\*') {
            $suffix = $expanded.Substring('%TOMATO_ROOT%'.Length).TrimStart('/', [char]'\')
            $expanded = Join-Path $tomatoRoot $suffix
        }
    }

    if (-not $ResolveRelative) {
        return $expanded
    }

    if (-not [System.IO.Path]::IsPathRooted($expanded)) {
        $baseDir = ([string]$BasePath ?? '').Trim()
        if (-not $baseDir) {
            $baseDir = if ($tomatoRoot) { $tomatoRoot } else { (Get-Location).Path }
        }

        $expanded = Join-Path $baseDir $expanded
    }

    try {
        return [System.IO.Path]::GetFullPath($expanded)
    }
    catch {
        return $expanded
    }
}

Export-ModuleMember -Function Resolve-TomatoRootPath
