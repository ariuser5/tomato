# -----------------------------------------------------------------------------
# Create-DraftEmail.ps1
# -----------------------------------------------------------------------------
# Runs draft-email creation for a configured flow.
#
# Behavior:
#   - If a repository-level override script exists at:
#       $env:TOMATO_ROOT/automations/Create-DraftEmail.ps1
#     it is executed.
#   - Otherwise this script reports a no-op (base layer has no default draft
#     implementation).
# -----------------------------------------------------------------------------
[CmdletBinding()]
param(
    [Parameter()]
    [string]$FlowName,

    [Parameter()]
    [string]$Path,

    [Parameter()]
    [ValidateSet('Auto', 'Local', 'Remote')]
    [string]$PathType = 'Auto'
)

$ErrorActionPreference = 'Stop'

$resultUtilsModule = Join-Path $PSScriptRoot '..\..\utils\common\ResultUtils.psm1'
Import-Module $resultUtilsModule -Force

$tomatoRoot = ([string]$env:TOMATO_ROOT ?? '').Trim()
$customDraftScript = if ($tomatoRoot) {
    Join-Path $tomatoRoot 'automations\Create-DraftEmail.ps1'
} else {
    $null
}

if ($customDraftScript -and (Test-Path -LiteralPath $customDraftScript -PathType Leaf)) {
    Write-Host "Running custom draft automation: $customDraftScript" -ForegroundColor Yellow

    $invokeArgs = @{}
    if ($FlowName) { $invokeArgs.FlowName = $FlowName }
    if ($Path) { $invokeArgs.Path = $Path }
    if ($PathType) { $invokeArgs.PathType = $PathType }

    $invocationOutput = $null
    try {
        $invocationOutput = & $customDraftScript @invokeArgs
    }
    catch [System.Management.Automation.ParameterBindingException] {
        # Compatibility fallback for custom scripts with different signatures.
        $invocationOutput = & $customDraftScript
    }

    if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }

    if ($null -ne $invocationOutput) {
        Write-Output $invocationOutput
    }

    Write-Output (New-ToolResult -Status 'Completed' -Data @{
            FlowName = $FlowName
            Path = $Path
            PathType = $PathType
            Script = $customDraftScript
        })
    exit 0
}

Write-Host 'Draft email automation is not configured in this repository yet. Skipping.' -ForegroundColor DarkYellow
Write-Output (New-ToolResult -Status 'NoOp' -Data @{
        FlowName = $FlowName
        Path = $Path
        PathType = $PathType
        Message = 'No custom draft automation script found under TOMATO_ROOT/automations.'
    })

exit 0
