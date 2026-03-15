<#
-------------------------------------------------------------------------------
Start-Main.ps1
-------------------------------------------------------------------------------
Interactive entrypoint for entity automations.

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

$entityConfigModule = Join-Path $baseRoot '.\helpers\EntityConfig.psm1'
Import-Module $entityConfigModule -Force

$automationConfigModule = Join-Path $baseRoot '.\helpers\AutomationConfig.psm1'
Import-Module $automationConfigModule -Force

$init = Initialize-EntityConfig -AppRoot $baseRoot
$Config = $init.Config

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

function Start-Preview {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Title
    )

    $previewScript = Join-Path $baseRoot '.\utils\Preview-Location.ps1'
    $previewScript = (Resolve-Path -LiteralPath $previewScript -ErrorAction Stop).Path

    $previewRoot = ($Root ?? '').Trim()
    if (-not $previewRoot) {
        throw 'Empty preview root.'
    }

    $previewArgs = @(
        '-Root', $previewRoot,
        '-Title', $Title
    )

    if ($Config.PreviewMaxDepth -and $Config.PreviewMaxDepth -gt 0) {
        $previewArgs += @('-MaxDepth', [string]$Config.PreviewMaxDepth)
    }

    # Invoke via pwsh to avoid argument-binding edge cases when invoking a script path directly.
    & pwsh -NoProfile -File $previewScript @previewArgs
}

function Prompt-Choice {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt,
        [Parameter(Mandatory = $true)][string[]]$Valid
    )

    while ($true) {
        $c = (Read-Host $Prompt)
        if ($null -eq $c) { continue }
        $c = $c.Trim()
        foreach ($v in $Valid) {
            if ($c.Equals($v, [System.StringComparison]::OrdinalIgnoreCase)) {
                return $v
            }
        }
        Write-Warn "Invalid choice. Valid: $($Valid -join ', ')"
    }
}

function Select-FromList {
    param(
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyCollection()][object[]]$Items,
        [Parameter()][string]$ItemLabel = 'item',
        [Parameter()][switch]$AllowQuit
    )

    Write-Heading $Title

    if (-not $Items -or $Items.Count -eq 0) {
        Write-Warn "No $ItemLabel found."
        Write-Host ''
        Read-Host 'Press Enter to go back'
        return $null
    }

    for ($i = 0; $i -lt $Items.Count; $i++) {
        $n = $i + 1
        Write-Host ("[{0}] {1}" -f $n, $Items[$i].Name) -ForegroundColor Gray
    }

    Write-Host ''
    if ($AllowQuit) {
        Write-Info "Type a number, 'b' to go back, or 'q' to quit."
    } else {
        Write-Info "Type a number, or 'b' to go back."
    }

    while ($true) {
        $raw = Read-Host 'Select'
        if ($null -eq $raw) { continue }
        $raw = $raw.Trim()

        if ($raw.Equals('b', [System.StringComparison]::OrdinalIgnoreCase)) {
            return $null
        }

        if ($AllowQuit -and $raw.Equals('q', [System.StringComparison]::OrdinalIgnoreCase)) {
            Request-Quit
            return $null
        }

        $n = 0
        if ([int]::TryParse($raw, [ref]$n)) {
            if ($n -ge 1 -and $n -le $Items.Count) {
                return $Items[$n - 1]
            }
        }

        Write-Warn 'Invalid selection.'
    }
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

function Browse-Clients {
    $clients = Resolve-Clients -Config $Config

    while ($true) {
        Clear-Host
        Write-Heading 'Clients'
        Write-Info "Count: $($clients.Count)"
        Write-Host ''

        $client = Select-FromList -Title 'Select client' -Items $clients -ItemLabel 'clients' -AllowQuit
        if (-not $client) { return }

        Start-Preview -Root $client.Root -Title "Client preview: $($client.Name)"
    }
}

function Preview-Accountant {
    $accountants = Resolve-Accountants -Config $Config
    if (-not $accountants -or $accountants.Count -eq 0) {
        throw 'No accountants are configured. Set parties.json (accountants[]).'
    }

    while ($true) {
        Clear-Host
        Write-Heading 'Accountants'
        Write-Info "Count: $($accountants.Count)"
        Write-Host ''

        $accountant = Select-FromList -Title 'Select accountant' -Items $accountants -ItemLabel 'accountants' -AllowQuit
        if (-not $accountant) { return }

        Start-Preview -Root $accountant.Root -Title "Accountant preview: $($accountant.Name)"
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
    $currentNode = $rootNode
    $parentStack = @()
    $breadcrumb = @()

    while ($true) {
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
        } else {
            for ($i = 0; $i -lt $menuItems.Count; $i++) {
                $idx = $i + 1
                $item = $menuItems[$i]

                if ($item.Type -eq 'Folder') {
                    Write-Host ("[{0}] + {1}/" -f $idx, $item.Label) -ForegroundColor Gray
                } else {
                    Write-Host ("[{0}] - {1}" -f $idx, $item.Label) -ForegroundColor Gray
                }
            }
        }

        Write-Host ''
        if ($breadcrumb.Count -gt 0) {
            Write-Info "Type a number, 'b' for back, or 'h' for home."
        } else {
            Write-Info "Type a number, 'b' to return to the main menu, or 'h' for home."
        }

        $raw = Read-Host 'Select'
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

function Show-Settings {
    Clear-Host
    Write-Heading 'Settings'

    $accountants = Resolve-Accountants -Config $Config
    if (-not $accountants -or $accountants.Count -eq 0) {
        Write-Warn 'Accountants: (none configured)'
    } else {
        Write-Info "Accountants ($($accountants.Count)):\n"
        foreach ($a in $accountants) {
            Write-Host ("- {0} -> {1}" -f $a.Name, $a.Root) -ForegroundColor Gray
        }
    }

    $clients = Resolve-Clients -Config $Config
    if (-not $clients -or $clients.Count -eq 0) {
        Write-Warn 'Clients: (none configured)'
    } else {
        Write-Info "Clients ($($clients.Count)):\n"
        foreach ($c in $clients) {
            Write-Host ("- {0} -> {1}" -f $c.Name, $c.Root) -ForegroundColor Gray
        }
    }

    Write-Host ''
    $automationConfigPaths = Get-AutomationConfigPaths -AppRoot $baseRoot
    Write-Info "Automation config (active): $($automationConfigPaths.Public)"
    Write-Info "Automation config (preferred): $($automationConfigPaths.Preferred)"

    $automationCount = (Get-Automations -AppRoot $baseRoot).Count
    Write-Info "Configured automations: $automationCount"

    Write-Host ''
    $partiesConfigPath = Join-Path $PSScriptRoot 'conf/parties.json'
    Write-Info "Parties config: $partiesConfigPath"

    Write-Host ''
    Write-Info 'Environment variables:'
    Write-Info "- TOMATO_ROOT: $($env:TOMATO_ROOT)"
    Write-Info "- BASE_DIR: $($env:BASE_DIR)"
    Write-Info "- UTILS_ROOT: $($env:UTILS_ROOT)"
    Write-Host ''
    Read-Host 'Press Enter to go back'
}

# -----------------------------------------------------------------------------
# Main loop
# -----------------------------------------------------------------------------

Assert-Interactive

while ($true) {
    if ($script:__ShouldQuit) { break }
    Clear-Host

    Write-Heading 'Entity automation entrypoint'
    $clientCount = (Resolve-Clients -Config $Config).Count
    Write-Info "Clients: $clientCount"
    Write-Host ''

    Write-Host '[1] Automations' -ForegroundColor Gray
    Write-Host '[2] Settings' -ForegroundColor Gray
    Write-Host '[3] Quit' -ForegroundColor Gray

    Write-Host ''
    $choice = Read-Host 'Select'
    if ($null -eq $choice) { continue }
    $choice = $choice.Trim()

    try {
        switch ($choice) {
            '1' { Automations-Menu }
            '2' { Show-Settings }
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
