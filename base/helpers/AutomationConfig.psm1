<#
-------------------------------------------------------------------------------
AutomationConfig.psm1
-------------------------------------------------------------------------------
Shared helpers for entity automation command config.

Responsibilities:
    - Resolve config file path
  - Parse/validate config JSON entries
    - Build merged automation entries
  - Execute automation commands

Exported functions:
  - Get-AutomationConfigPaths
  - Get-Automations
  - Invoke-AutomationCommand
-------------------------------------------------------------------------------
#>

function Get-AutomationConfigPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$AppRoot
    )

    $tomatoRoot = Split-Path $AppRoot -Parent
    $preferredConfigPath = Join-Path $tomatoRoot 'conf/automations.json'
    $legacyConfigPath = Join-Path $AppRoot 'conf/automations.json'
    $legacyRootConfigPath = Join-Path $AppRoot 'automations.json'

    $publicConfigPath = $preferredConfigPath
    if (-not (Test-Path -LiteralPath $preferredConfigPath -PathType Leaf) -and (Test-Path -LiteralPath $legacyConfigPath -PathType Leaf)) {
        $publicConfigPath = $legacyConfigPath
    }

    return [pscustomobject]@{
        Public    = $publicConfigPath
        Preferred = $preferredConfigPath
        Legacy    = $legacyConfigPath
        LegacyRoot = $legacyRootConfigPath
    }
}

function Read-AutomationEntriesFromFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ConfigPath,
        [Parameter()][hashtable]$Visited = @{}
    )

    function Read-AutomationEntriesFromFileCore {
        param(
            [Parameter(Mandatory = $true)][string]$CurrentPath,
            [Parameter(Mandatory = $true)][hashtable]$VisitedMap
        )

        if (-not (Test-Path -LiteralPath $CurrentPath -PathType Leaf)) {
            return @()
        }

        $resolvedPath = $CurrentPath
        try {
            $resolvedPath = (Resolve-Path -LiteralPath $CurrentPath -ErrorAction Stop).Path
        } catch {
            return @()
        }

        if ($VisitedMap.ContainsKey($resolvedPath)) {
            return @()
        }
        $VisitedMap[$resolvedPath] = $true

        $raw = $null
        try {
            $raw = Get-Content -LiteralPath $resolvedPath -Raw -Encoding UTF8 -ErrorAction Stop
        } catch {
            return @()
        }

        if (-not $raw -or -not $raw.Trim()) {
            return @()
        }

        $parsed = $null
        try {
            $parsed = $raw | ConvertFrom-Json -ErrorAction Stop
        } catch {
            return @()
        }

        $entries = @()
        if ($parsed -is [array]) {
            $entries = @($parsed)
        } elseif ($parsed.PSObject.Properties.Name -contains 'automations') {
            $entries = @($parsed.automations)
        } else {
            return @()
        }

        $baseDir = Split-Path -Parent $resolvedPath
        $result = @()

        foreach ($entry in $entries) {
            if ($null -eq $entry) { continue }

            $hasImport = $entry.PSObject.Properties.Name -contains 'import'
            $hasAlias = $entry.PSObject.Properties.Name -contains 'alias'
            $hasCommand = $entry.PSObject.Properties.Name -contains 'command'

            if ($hasImport) {
                $importSpec = $entry.import
                if ($null -eq $importSpec) { continue }

                if (-not ($importSpec.PSObject.Properties.Name -contains 'path')) {
                    continue
                }

                $importValue = ([string]$importSpec.path ?? '').Trim()
                if (-not $importValue) { continue }

                try {
                    $importValue = $ExecutionContext.InvokeCommand.ExpandString($importValue)
                } catch {
                    continue
                }

                $importPath = if ([System.IO.Path]::IsPathRooted($importValue)) {
                    $importValue
                } else {
                    Join-Path -Path $baseDir -ChildPath $importValue
                }

                $result += @(Read-AutomationEntriesFromFileCore -CurrentPath $importPath -VisitedMap $VisitedMap)
                continue
            }

            if (-not $hasAlias -or -not $hasCommand) { continue }

            $alias = ([string]$entry.alias ?? '').Trim()
            $command = ([string]$entry.command ?? '').Trim()
            if (-not $alias -or -not $command) { continue }

            $hasCategoryPath = $entry.PSObject.Properties.Name -contains 'categoryPath'
            if (-not $hasCategoryPath) {
                Write-Warning "Skipping automation '$alias' in '$resolvedPath': missing required categoryPath array."
                continue
            }

            $categoryPathValue = $entry.categoryPath
            if (-not ($categoryPathValue -is [array])) {
                Write-Warning "Skipping automation '$alias' in '$resolvedPath': categoryPath must be an array of strings."
                continue
            }

            $categoryPath = @()
            foreach ($segment in @($categoryPathValue)) {
                if ($null -eq $segment) { continue }
                $segmentText = ([string]$segment).Trim()
                if (-not $segmentText) { continue }
                $categoryPath += $segmentText
            }

            $result += [pscustomobject]@{
                Name         = $alias
                Alias        = $alias
                Command      = $command
                CategoryPath = @($categoryPath)
                Source       = $resolvedPath
            }
        }

        return @($result)
    }

    return @(Read-AutomationEntriesFromFileCore -CurrentPath $ConfigPath -VisitedMap $Visited)
}

function Get-Automations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$AppRoot
    )

    $paths = Get-AutomationConfigPaths -AppRoot $AppRoot

    $mergedByKey = @{}
    $orderedKeys = @()

    function Get-AutomationMergeKey {
        param([Parameter(Mandatory = $true)][object]$Entry)

        $alias = if ($Entry.PSObject.Properties.Name -contains 'Alias') { ([string]$Entry.Alias ?? '').Trim() } else { '' }

        $categorySegments = @()
        if ($Entry.PSObject.Properties.Name -contains 'CategoryPath' -and $Entry.CategoryPath -is [array]) {
            $categorySegments = @(
                @($Entry.CategoryPath) |
                    ForEach-Object { ([string]$_ ?? '').Trim() } |
                    Where-Object { $_ }
            )
        }

        $categoryKey = if ($categorySegments.Count -gt 0) { $categorySegments -join '/' } else { '' }
        return "{0}|{1}" -f $categoryKey, $alias
    }

    $configs = @($paths.LegacyRoot, $paths.Legacy, $paths.Preferred) | Select-Object -Unique

    foreach ($configPath in $configs) {
        $entries = @(Read-AutomationEntriesFromFile -ConfigPath $configPath)
        foreach ($entry in $entries) {
            $entryKey = Get-AutomationMergeKey -Entry $entry
            if (-not $mergedByKey.ContainsKey($entryKey)) {
                $orderedKeys += $entryKey
            }
            $mergedByKey[$entryKey] = $entry
        }
    }

    $result = @()
    foreach ($entryKey in $orderedKeys) {
        $result += $mergedByKey[$entryKey]
    }

    return @($result)
}

function Invoke-AutomationCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Alias,
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string]$AppRoot,
        [Parameter()][string]$WorkingDirectory
    )

    $tomatoRoot = Split-Path $AppRoot -Parent
    $env:TOMATO_ROOT = $tomatoRoot
    $env:BASE_DIR = $AppRoot
    $env:UTILS_ROOT = Join-Path $AppRoot 'utils'

    $effectiveWorkingDirectory = $AppRoot
    if ($WorkingDirectory -and (Test-Path -LiteralPath $WorkingDirectory -PathType Container)) {
        try {
            $effectiveWorkingDirectory = (Resolve-Path -LiteralPath $WorkingDirectory -ErrorAction Stop).Path
        } catch {
            $effectiveWorkingDirectory = $AppRoot
        }
    }

    $previousLocation = Get-Location
    $previousLastExitCode = $global:LASTEXITCODE

    try {
        Set-Location -LiteralPath $effectiveWorkingDirectory
        $global:LASTEXITCODE = $null

        # Execute in-process so interactive scripts can use the active console host.
        Invoke-Expression $Command

        if ($null -ne $LASTEXITCODE) {
            return $LASTEXITCODE
        }

        if ($?) {
            return 0
        }

        return 1
    } catch {
        Write-Host $_.Exception.Message -ForegroundColor Red
        return 1
    } finally {
        Set-Location -LiteralPath $previousLocation
        $global:LASTEXITCODE = $previousLastExitCode
    }
}

Export-ModuleMember -Function Get-AutomationConfigPaths, Get-Automations, Invoke-AutomationCommand
