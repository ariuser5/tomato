# -----------------------------------------------------------------------------
# Run-SingleScript.ps1
# -----------------------------------------------------------------------------
# Generic Tomatoflow automation wrapper.
#
# Design:
# - Keep wrapper logic minimal.
# - Forward only P-prefixed args to the target script.
# - Optional prompt marker for path/name parameters.
#
# Pass-through convention:
# - Remaining args prefixed with -P are forwarded without the P.
#   Example: -PMailerParamFile value => -MailerParamFile value
#
# Prompt convention:
# - Pass value '$Prompt' to -PPath or -PTargetFolderName to trigger
#   interactive month-subfolder selection.
# -----------------------------------------------------------------------------

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ScriptPath,

    [Parameter(ValueFromRemainingArguments = $true)]
    [AllowEmptyCollection()]
    [string[]]$PassThroughArgs = @()
)

$ErrorActionPreference = 'Stop'

$flowTargetUtilsModule = Join-Path $PSScriptRoot '.\modules\FlowTargetUtils.psm1'
Import-Module $flowTargetUtilsModule -Force

$resultUtilsModule = Join-Path $PSScriptRoot '..\..\utils\common\ResultUtils.psm1'
Import-Module $resultUtilsModule -Force

function Resolve-GenericScriptPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RawPath
    )

    $expanded = ([string]$RawPath ?? '').Trim()
    if (-not $expanded) {
        throw '-ScriptPath is required.'
    }

    try {
        $expanded = $ExecutionContext.InvokeCommand.ExpandString($expanded)
    }
    catch {
        # Keep raw value when expansion fails.
    }

    $candidate = $expanded
    $hasSeparator = ($expanded.IndexOf([System.IO.Path]::DirectorySeparatorChar) -ge 0) -or ($expanded.IndexOf([System.IO.Path]::AltDirectorySeparatorChar) -ge 0)
    $hasExtension = ([System.IO.Path]::GetExtension($expanded) ?? '') -ne ''

    if (-not [System.IO.Path]::IsPathRooted($candidate)) {
        if (-not $hasSeparator -and -not $hasExtension) {
            $siblingCandidate = Join-Path $PSScriptRoot ($expanded + '.ps1')
            if (Test-Path -LiteralPath $siblingCandidate -PathType Leaf) {
                $candidate = $siblingCandidate
            }
            else {
                $candidate = Join-Path (Join-Path $PSScriptRoot 'scripts') ($expanded + '.ps1')
            }
        }
        elseif (-not $hasSeparator -and $hasExtension) {
            $siblingCandidate = Join-Path $PSScriptRoot $expanded
            if (Test-Path -LiteralPath $siblingCandidate -PathType Leaf) {
                $candidate = $siblingCandidate
            }
            else {
                $candidate = Join-Path (Join-Path $PSScriptRoot 'scripts') $expanded
            }
        }
        else {
            $candidate = Join-Path $PSScriptRoot $expanded
        }
    }

    return (Resolve-Path -LiteralPath $candidate -ErrorAction Stop).Path
}

function Convert-PassThroughValue {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$Value
    )

    if ($null -eq $Value) {
        return $null
    }

    $text = ([string]$Value ?? '').Trim()
    if ($text -match '^(?i:true)$') { return $true }
    if ($text -match '^(?i:false)$') { return $false }

    return $Value
}

function Parse-PassThroughArgs {
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$RawArgs = @()
    )

    $result = @{}
    $tokens = @($RawArgs)

    for ($i = 0; $i -lt $tokens.Count; $i++) {
        $token = ([string]$tokens[$i] ?? '').Trim()
        if (-not $token) {
            continue
        }

        if ($token -notmatch '^-{1,2}P([A-Za-z_][A-Za-z0-9_-]*)(?::)?$') {
            throw "Unsupported pass-through token '$token'. Use -P<ParameterName> [value]."
        }

        $paramName = $Matches[1]
        $value = $true

        if (($i + 1) -lt $tokens.Count) {
            $next = ([string]$tokens[$i + 1] ?? '').Trim()
            if ($next -and ($next -notmatch '^-{1,2}P([A-Za-z_][A-Za-z0-9_-]*)(?::)?$')) {
                $value = Convert-PassThroughValue -Value $next
                $i++
            }
        }

        if ($result.ContainsKey($paramName)) {
            $existing = $result[$paramName]
            if ($existing -is [System.Array]) {
                $result[$paramName] = @($existing + $value)
            }
            else {
                $result[$paramName] = @($existing, $value)
            }
        }
        else {
            $result[$paramName] = $value
        }
    }

    return $result
}

function Resolve-PathPromptValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$InvokeArgs,

        [Parameter(Mandatory = $true)]
        [string]$PromptMarker,

        [Parameter(Mandatory = $true)]
        [string]$PromptLabel,

        [Parameter(Mandatory = $true)]
        [string]$TargetScriptPath
    )

    if (-not $InvokeArgs.ContainsKey('Path')) {
        return
    }

    $rawPathValue = ([string]$InvokeArgs.Path ?? '').Trim()
    if ($rawPathValue -ne $PromptMarker) {
        return
    }

    $rootPath = ''
    foreach ($candidate in @('StoragePath')) {
        if ($InvokeArgs.ContainsKey($candidate)) {
            $candidateValue = ([string]$InvokeArgs[$candidate] ?? '').Trim()
            if ($candidateValue) {
                $rootPath = $candidateValue
                break
            }
        }
    }

    if (-not $rootPath) {
        throw "Cannot resolve 'Path' from '$PromptMarker': expected -PStoragePath."
    }

    $pathType = 'Auto'
    if ($InvokeArgs.ContainsKey('PathType')) {
        $candidatePathType = ([string]$InvokeArgs.PathType ?? '').Trim()
        if ($candidatePathType) {
            $pathType = $candidatePathType
        }
    }

    $target = Resolve-FlowTargetPath -RootPath $rootPath -PathType $pathType -PromptLabel $PromptLabel
    if ($target.Status -eq 'Aborted') {
        Write-Host 'Action aborted (ESC).' -ForegroundColor DarkYellow
        Write-Output (New-ToolResult -Status 'Aborted' -Data @{
                Script = $TargetScriptPath
                RootPath = $rootPath
                PathType = $pathType
            })
        exit 0
    }

    if ($target.UsedFallback) {
        Write-Host "Using latest month folder: $($target.SubfolderName)" -ForegroundColor Gray
    }

    $InvokeArgs.Path = $target.TargetPath
}

function Resolve-TargetFolderNamePromptValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$InvokeArgs,

        [Parameter(Mandatory = $true)]
        [string]$PromptMarker,

        [Parameter(Mandatory = $true)]
        [string]$PromptLabel,

        [Parameter(Mandatory = $true)]
        [string]$TargetScriptPath
    )

    if (-not $InvokeArgs.ContainsKey('TargetFolderName')) {
        return
    }

    $rawValue = ([string]$InvokeArgs.TargetFolderName ?? '').Trim()
    if ($rawValue -ne $PromptMarker) {
        return
    }

    $rootPath = ''
    foreach ($candidate in @('Path', 'StoragePath')) {
        if ($InvokeArgs.ContainsKey($candidate)) {
            $candidateValue = ([string]$InvokeArgs[$candidate] ?? '').Trim()
            if ($candidateValue) {
                $rootPath = $candidateValue
                break
            }
        }
    }

    if (-not $rootPath) {
        throw "Cannot resolve 'TargetFolderName' from '$PromptMarker': expected one of -PPath or -PStoragePath."
    }

    $pathType = 'Auto'
    if ($InvokeArgs.ContainsKey('PathType')) {
        $candidatePathType = ([string]$InvokeArgs.PathType ?? '').Trim()
        if ($candidatePathType) {
            $pathType = $candidatePathType
        }
    }

    $target = Resolve-FlowTargetPath -RootPath $rootPath -PathType $pathType -PromptLabel $PromptLabel
    if ($target.Status -eq 'Aborted') {
        Write-Host 'Action aborted (ESC).' -ForegroundColor DarkYellow
        Write-Output (New-ToolResult -Status 'Aborted' -Data @{
                Script = $TargetScriptPath
                RootPath = $rootPath
                PathType = $pathType
            })
        exit 0
    }

    if ($target.UsedFallback) {
        Write-Host "Using latest month folder: $($target.SubfolderName)" -ForegroundColor Gray
    }

    $InvokeArgs.TargetFolderName = $target.SubfolderName
}

function Remove-HelperOnlyArgs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$InvokeArgs
    )

    foreach ($helperName in @('StoragePath')) {
        if ($InvokeArgs.ContainsKey($helperName)) {
            $null = $InvokeArgs.Remove($helperName)
        }
    }
}

$targetScript = Resolve-GenericScriptPath -RawPath $ScriptPath
$invokeArgs = Parse-PassThroughArgs -RawArgs $PassThroughArgs

$promptMarker = '$Prompt'

$promptLabel = ((Split-Path -Leaf $targetScript) -replace '\.ps1$', '') -replace '[-_]+', ' '
$promptLabel = $promptLabel.ToLowerInvariant()

Resolve-PathPromptValue -InvokeArgs $invokeArgs -PromptMarker $promptMarker -PromptLabel $promptLabel -TargetScriptPath $targetScript
Resolve-TargetFolderNamePromptValue -InvokeArgs $invokeArgs -PromptMarker $promptMarker -PromptLabel $promptLabel -TargetScriptPath $targetScript

Remove-HelperOnlyArgs -InvokeArgs $invokeArgs

& $targetScript @invokeArgs