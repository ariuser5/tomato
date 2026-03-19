Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$pathModule = Join-Path $PSScriptRoot '..\..\..\utils\PathUtils.psm1'
Import-Module $pathModule -Force

$monthUtilsModule = Join-Path $PSScriptRoot '..\..\organization\modules\MonthUtils.psm1'
Import-Module $monthUtilsModule -Force

$commandUtilsModule = Join-Path $PSScriptRoot '..\..\..\utils\common\CommandUtils.psm1'
Import-Module $commandUtilsModule -Force

function Read-InputWithEsc {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt
    )

    if (-not $Host.UI -or -not $Host.UI.RawUI) {
        $value = Read-Host $Prompt
        return [pscustomobject]@{ Status = 'Submitted'; Value = [string]$value }
    }

    Write-Host ("{0}: " -f $Prompt) -NoNewline
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
            Write-Host ''
            return [pscustomobject]@{ Status = 'Escaped'; Value = '' }
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

function Get-LatestMonthSubfolderName {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter()]
        [ValidateSet('Auto', 'Local', 'Remote')]
        [string]$PathType = 'Auto'
    )

    $rootInfo = Resolve-UnifiedPath -Path $RootPath -PathType $PathType

    $folders = @()
    if ($rootInfo.PathType -eq 'Remote') {
        Assert-RcloneAvailable
        $folders = @(
            Invoke-Rclone -Arguments @('lsf', $rootInfo.Normalized, '--dirs-only') -ErrorMessage "Failed to list remote directory '$($rootInfo.Normalized)'."
        )
        $folders = @(
            $folders |
                Where-Object { $_ -ne $null -and $_ -ne '' } |
                ForEach-Object { $_.TrimEnd('/') }
        )
    }
    else {
        if (-not (Test-Path -LiteralPath $rootInfo.LocalPath -PathType Container)) {
            throw "Root path does not exist: $($rootInfo.LocalPath)"
        }

        $folders = @(
            Get-ChildItem -LiteralPath $rootInfo.LocalPath -Directory -ErrorAction Stop |
                Select-Object -ExpandProperty Name
        )
    }

    return (Get-LastMonthValue -Values $folders -SkipInvalid)
}

function Get-LatestMonthTargetPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter()]
        [ValidateSet('Auto', 'Local', 'Remote')]
        [string]$PathType = 'Auto'
    )

    $rootInfo = Resolve-UnifiedPath -Path $RootPath -PathType $PathType
    $latestMonth = Get-LatestMonthSubfolderName -RootPath $RootPath -PathType $PathType
    if (-not $latestMonth) {
        return $null
    }

    return (Join-UnifiedPath -Base $rootInfo.Normalized -Child $latestMonth -PathType $rootInfo.PathType)
}

function Resolve-FlowTargetPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath,

        [Parameter()]
        [ValidateSet('Auto', 'Local', 'Remote')]
        [string]$PathType = 'Auto',

        [Parameter()]
        [string]$Subfolder,

        [Parameter()]
        [string]$PromptLabel = 'target subfolder'
    )

    $rootInfo = Resolve-UnifiedPath -Path $RootPath -PathType $PathType

    $resolvedSubfolder = ([string]$Subfolder ?? '').Trim()
    $latestMonthPath = Get-LatestMonthTargetPath -RootPath $RootPath -PathType $PathType
    $latestMonth = if ($latestMonthPath) { (Split-Path -Leaf $latestMonthPath) } else { $null }

    if (-not $resolvedSubfolder) {
        $fallbackText = if ($latestMonth) { $latestMonth } else { '<none found>' }
        $promptResult = Read-InputWithEsc -Prompt ("Enter subfolder for {0} (Enter = latest month: {1}, ESC = abort)" -f $PromptLabel, $fallbackText)
        if ($promptResult.Status -eq 'Escaped') {
            return [pscustomobject]@{
                Status        = 'Aborted'
                RootPath      = $rootInfo.Normalized
                TargetPath    = $null
                SubfolderName = $null
                UsedFallback  = $false
            }
        }

        $resolvedSubfolder = ([string]$promptResult.Value ?? '').Trim()
    }

    $usedFallback = $false
    if (-not $resolvedSubfolder) {
        if (-not $latestMonth) {
            throw "No month folder found under '$($rootInfo.Normalized)' to use as fallback target."
        }

        $resolvedSubfolder = $latestMonth
        $usedFallback = $true
    }

    $targetPath = Join-UnifiedPath -Base $rootInfo.Normalized -Child $resolvedSubfolder -PathType $rootInfo.PathType

    return [pscustomobject]@{
        Status        = 'Resolved'
        RootPath      = $rootInfo.Normalized
        TargetPath    = $targetPath
        SubfolderName = $resolvedSubfolder
        UsedFallback  = $usedFallback
    }
}

Export-ModuleMember -Function Read-InputWithEsc, Get-LatestMonthSubfolderName, Get-LatestMonthTargetPath, Resolve-FlowTargetPath
