<#
-------------------------------------------------------------------------------
SettingsView.psm1
-------------------------------------------------------------------------------
Renders the Settings view for the interactive main entrypoint.
-------------------------------------------------------------------------------
#>

$automationConfigModule = Join-Path $PSScriptRoot 'AutomationConfig.psm1'
Import-Module $automationConfigModule -Force

function Show-SettingsView {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$AppRoot
    )

    Clear-Host
    Write-Host 'Settings' -ForegroundColor Cyan

    Write-Host ''
    $automationConfigPaths = Get-AutomationConfigPaths -AppRoot $AppRoot
    Write-Host "Automation config (active): $($automationConfigPaths.Public)" -ForegroundColor Gray
    Write-Host "Automation config (preferred): $($automationConfigPaths.Preferred)" -ForegroundColor Gray

    $automationCount = (Get-Automations -AppRoot $AppRoot).Count
    Write-Host "Configured automations: $automationCount" -ForegroundColor Gray

    Write-Host ''
    Write-Host 'Environment variables:' -ForegroundColor Gray
    Write-Host "- TOMATO_ROOT: $($env:TOMATO_ROOT)" -ForegroundColor Gray
    Write-Host "- BASE_DIR: $($env:BASE_DIR)" -ForegroundColor Gray
    Write-Host "- UTILS_ROOT: $($env:UTILS_ROOT)" -ForegroundColor Gray
    Write-Host ''
    Read-Host 'Press Enter to go back' | Out-Null
}

Export-ModuleMember -Function Show-SettingsView
