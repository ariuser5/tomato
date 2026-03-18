<#
-------------------------------------------------------------------------------
Start-Main.ps1
-------------------------------------------------------------------------------
Interactive entrypoint for automations.

Goals:
    - Read-only navigation/preview of folder structures (interactive, folder-only navigation)
  - Works against local filesystem OR Google Drive via rclone
    - Launches automations from JSON command configs

Notes:
  - This script intentionally does NOT implement workflow logic (month close, labels,
    archival, emailing, etc). It only helps you explore and jump into existing tools.
        - The navigation preview UI is implemented by: base/utils/Preview-Location.ps1
-------------------------------------------------------------------------------
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

$baseRoot = Join-Path $PSScriptRoot 'base'

if (-not (Test-Path -LiteralPath $baseRoot -PathType Container)) {
    throw "Missing required base folder: $baseRoot"
}

$automationConfigModule = Join-Path $baseRoot '.\helpers\AutomationConfig.psm1'
Import-Module $automationConfigModule -Force

$settingsViewModule = Join-Path $baseRoot '.\helpers\SettingsView.psm1'
Import-Module $settingsViewModule -Force

$viewOptionSelectorScript = Join-Path $baseRoot '.\utils\Select-ViewOption.ps1'
if (-not (Test-Path -LiteralPath $viewOptionSelectorScript -PathType Leaf)) {
    throw "Missing required view option selector: $viewOptionSelectorScript"
}

function Write-Heading {
    param([Parameter(Mandatory = $true)][string]$Text)
    Write-Host $Text -ForegroundColor Cyan
}

function Write-Info {
    param([Parameter(Mandatory = $true)][string]$Text)
    Write-Host $Text -ForegroundColor Gray
}

function Write-Warn {
    param([Parameter(Mandatory = $true)][string]$Text)
    Write-Host $Text -ForegroundColor Yellow
}

function Write-Err {
    param([Parameter(Mandatory = $true)][string]$Text)
    Write-Host $Text -ForegroundColor Red
}

function Assert-Interactive {
    # Fail fast in non-interactive contexts.
    if (-not $Host.UI -or -not $Host.UI.RawUI) {
        throw 'This script is interactive and requires a console host.'
    }
}

function Request-Quit {
    $script:__ShouldQuit = $true
}

function Wait-ForKeyPress {
    param([Parameter(Mandatory = $true)][string]$Prompt)

    Write-Info $Prompt
    if ($Host.UI -and $Host.UI.RawUI) {
        [void]$Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown')
    } else {
        Read-Host 'Press Enter to continue' | Out-Null
    }
}

function Request-ViewSelection {
    param(
        [Parameter(Mandatory = $true)][string[]]$Items,
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter()]
        [ValidateSet('ClearInput', 'ExitView', 'GoBack')]
        [string]$EscBehavior = 'ExitView'
    )

    $result = & $viewOptionSelectorScript -Items $Items -RenderStyle Numbered -Prompt $Prompt -LoopUntilNonEmpty:$true -TrimSelection -EscBehavior $EscBehavior
    if ($null -eq $result) {
        return ''
    }

    if ($result.PSObject.Properties.Name -contains 'Status') {
        $status = ([string]$result.Status ?? '').Trim()
        if ($status -eq 'GoBack') {
            return 'b'
        }
        if ($status -eq 'Escaped') {
            return ''
        }
    }

    if ($result.PSObject.Properties.Name -contains 'Selection') {
        return ([string]$result.Selection ?? '').Trim()
    }

    return ''
}


function New-AutomationFolderNode {
    param([Parameter(Mandatory = $true)][string]$Name)

    return [pscustomobject]@{
        Name        = $Name
        Folders     = @{}
        Automations = @()
    }
}

function New-AutomationTree {
    param(
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyCollection()][object[]]$Automations
    )

    $root = New-AutomationFolderNode -Name '/'

    foreach ($automation in @($Automations)) {
        if ($null -eq $automation) { continue }

        $pathSegments = @()
        if ($automation.PSObject.Properties.Name -contains 'CategoryPath' -and $null -ne $automation.CategoryPath) {
            $pathSegments = @($automation.CategoryPath)
        }

        $current = $root
        foreach ($segment in $pathSegments) {
            $segmentName = ([string]$segment ?? '').Trim()
            if (-not $segmentName) { continue }

            if (-not $current.Folders.ContainsKey($segmentName)) {
                $current.Folders[$segmentName] = New-AutomationFolderNode -Name $segmentName
            }

            $current = $current.Folders[$segmentName]
        }

        $current.Automations += $automation
    }

    return $root
}

function Get-AutomationWorkingDirectory {
    param([Parameter(Mandatory = $true)][object]$Automation)

    $workingDirectory = $baseRoot
    if ($Automation.PSObject.Properties.Name -contains 'Source' -and $Automation.Source) {
        try {
            $workingDirectory = Split-Path -Parent ([string]$Automation.Source)
        } catch {
            $workingDirectory = $baseRoot
        }
    }

    return $workingDirectory
}

function Remove-LastItem {
    param([Parameter()][object[]]$Items)

    if (-not $Items -or $Items.Count -le 1) {
        return @()
    }

    return @($Items[0..($Items.Count - 2)])
}

function Resolve-AutomationNavigation {
    param(
        [Parameter(Mandatory = $true)][object]$RootNode,
        [Parameter()][AllowNull()][AllowEmptyCollection()][string[]]$Breadcrumb
    )

    $current = $RootNode
    $parents = @()
    $resolvedBreadcrumb = @()

    foreach ($segment in @($Breadcrumb)) {
        $segmentName = ([string]$segment ?? '').Trim()
        if (-not $segmentName) { continue }

        if (-not $current.Folders.ContainsKey($segmentName)) {
            break
        }

        $parents += $current
        $current = $current.Folders[$segmentName]
        $resolvedBreadcrumb += $segmentName
    }

    return [pscustomobject]@{
        CurrentNode = $current
        ParentStack = $parents
        Breadcrumb  = $resolvedBreadcrumb
    }
}

function Run-Automation {
    param(
        [Parameter(Mandatory = $true)][string]$Alias,
        [Parameter(Mandatory = $true)][string]$Command,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory
    )

    # Set environment variables for automations
    $tomatoRoot = $PSScriptRoot
    $env:TOMATO_ROOT = $tomatoRoot
    $env:BASE_DIR = $baseRoot
    $env:UTILS_ROOT = Join-Path $baseRoot 'utils'

    Write-Host ''
    Write-Info "Running automation '$Alias'"
    Write-Info "Command: $Command"
    Write-Info "Working directory: $WorkingDirectory"
    Write-Host ''

    $exitCode = Invoke-AutomationCommand -Alias $Alias -Command $Command -AppRoot $baseRoot -WorkingDirectory $WorkingDirectory

    Write-Host ''
    Write-Info "Automation finished (exit code: $exitCode)"
    Write-Host ''
    Wait-ForKeyPress -Prompt 'Press any key to continue'
}


function Automations-Menu {
    $breadcrumb = @()

    while ($true) {
        $automations = @(Get-Automations -AppRoot $baseRoot)
        if (-not $automations -or $automations.Count -eq 0) {
            Clear-Host
            Write-Heading 'Automations'
            Write-Warn 'No automations found.'
            $paths = Get-AutomationConfigPaths -AppRoot $baseRoot
            Write-Info 'Expected config files:'
            Write-Info "- $($paths.Public)"
            Write-Host ''
            Read-Host 'Press Enter to go back'
            return
        }

        $rootNode = New-AutomationTree -Automations $automations
        $resolvedNavigation = Resolve-AutomationNavigation -RootNode $rootNode -Breadcrumb $breadcrumb
        $currentNode = $resolvedNavigation.CurrentNode
        $parentStack = $resolvedNavigation.ParentStack
        $breadcrumb = $resolvedNavigation.Breadcrumb

        Clear-Host
        Write-Heading 'Automations'

        if ($breadcrumb.Count -gt 0) {
            Write-Info ("Location: /{0}" -f ($breadcrumb -join '/'))
        } else {
            Write-Info 'Location: /'
        }
        Write-Host ''

        $menuItems = @()

        $folderNames = @($currentNode.Folders.Keys | Sort-Object)
        foreach ($folderName in $folderNames) {
            $menuItems += [pscustomobject]@{
                Type  = 'Folder'
                Label = $folderName
                Node  = $currentNode.Folders[$folderName]
            }
        }

        $automationItems = @($currentNode.Automations | Sort-Object Name)
        foreach ($automation in $automationItems) {
            $menuItems += [pscustomobject]@{
                Type       = 'Automation'
                Label      = $automation.Name
                Automation = $automation
            }
        }

        if ($menuItems.Count -eq 0) {
            Write-Warn 'This folder has no entries.'
        }

        Write-Host ''
        $selectionPrompt = ''
        if ($breadcrumb.Count -gt 0) {
            $selectionPrompt = "Type a number, 'b' for back, or 'h' for home"
        } else {
            $selectionPrompt = "Type a number, 'b' to return to the main menu, or 'h' for home"
        }

        $raw = ''
        if ($menuItems.Count -gt 0) {
            $displayItems = @()
            foreach ($item in $menuItems) {
                if ($item.Type -eq 'Folder') {
                    $displayItems += ("+ {0}/" -f $item.Label)
                }
                else {
                    $displayItems += ("- {0}" -f $item.Label)
                }
            }

            $raw = Request-ViewSelection -Items $displayItems -Prompt $selectionPrompt -EscBehavior GoBack
        }
        else {
            $raw = Read-Host $selectionPrompt
        }
        if ($null -eq $raw) { continue }
        $raw = $raw.Trim()

        if ($raw.Equals('b', [System.StringComparison]::OrdinalIgnoreCase)) {
            if ($breadcrumb.Count -eq 0) {
                return
            }

            $currentNode = $parentStack[$parentStack.Count - 1]
            $parentStack = Remove-LastItem -Items $parentStack
            $breadcrumb = Remove-LastItem -Items $breadcrumb
            continue
        }

        if ($raw.Equals('h', [System.StringComparison]::OrdinalIgnoreCase)) {
            $currentNode = $rootNode
            $parentStack = @()
            $breadcrumb = @()
            continue
        }

        $n = 0
        if (-not [int]::TryParse($raw, [ref]$n) -or $n -lt 1 -or $n -gt $menuItems.Count) {
            Write-Warn 'Invalid selection.'
            Start-Sleep -Milliseconds 700
            continue
        }

        $selected = $menuItems[$n - 1]
        if ($selected.Type -eq 'Folder') {
            $parentStack += $currentNode
            $currentNode = $selected.Node
            $breadcrumb += $selected.Label
            continue
        }

        $selectedAutomation = $selected.Automation
        if ($null -eq $selectedAutomation -or -not $selectedAutomation.Command) {
            Write-Warn 'Invalid automation entry.'
            Start-Sleep -Milliseconds 700
            continue
        }

        $workingDirectory = Get-AutomationWorkingDirectory -Automation $selectedAutomation
        Run-Automation -Alias $selectedAutomation.Alias -Command $selectedAutomation.Command -WorkingDirectory $workingDirectory
    }
}

# -----------------------------------------------------------------------------
# Main loop
# -----------------------------------------------------------------------------

Assert-Interactive

while ($true) {
    if ($script:__ShouldQuit) { break }
    Clear-Host

    Write-Heading 'Automation entrypoint'
    Write-Info 'Select a section.'
    Write-Host ''

    $mainItems = @(
        'Automations',
        'Settings',
        'Quit'
    )
    $choice = Request-ViewSelection -Items $mainItems -Prompt 'Select any option in the menu' -EscBehavior ExitView
    if ($null -eq $choice) { continue }
    $choice = $choice.Trim()

    if (-not $choice) {
        Request-Quit
        continue
    }

    try {
        switch ($choice) {
            '1' { Automations-Menu }
            '2' { Show-SettingsView -AppRoot $baseRoot }
            '3' { Request-Quit }
            default { Write-Warn 'Invalid selection.'; Start-Sleep -Milliseconds 700 }
        }
    } catch {
        Write-Err 'Error:'
        Write-Err $_.Exception.Message
        Write-Host ''
        Read-Host 'Press Enter to continue'
    }
}
