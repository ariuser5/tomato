# -----------------------------------------------------------------------------
# Create-DraftEmail.ps1
# -----------------------------------------------------------------------------
# Runs draft-email creation for a configured flow.
#
# Behavior:
#   - Uses `mailer draft --param-file` with base/resources/mailer-sample.json.
#   - Enriches param-file context.variables with flow/runtime values.
#   - If a repository-level override script exists at:
#       $env:TOMATO_ROOT/automations/Create-DraftEmail.ps1
#     it is executed.
#   - If no override exists, executes the default mailer-based flow.
# -----------------------------------------------------------------------------
[CmdletBinding()]
param(
    [Parameter()]
    [string]$FlowName,

    [Parameter()]
    [string]$Path,

    [Parameter()]
    [ValidateSet('Auto', 'Local', 'Remote')]
    [string]$PathType = 'Auto',

    [Parameter()]
    [string]$Subfolder
)

$ErrorActionPreference = 'Stop'

$commandUtilsModule = Join-Path $PSScriptRoot '..\..\utils\common\CommandUtils.psm1'
Import-Module $commandUtilsModule -Force

$resultUtilsModule = Join-Path $PSScriptRoot '..\..\utils\common\ResultUtils.psm1'
Import-Module $resultUtilsModule -Force

$flowTargetUtilsModule = Join-Path $PSScriptRoot '.\modules\FlowTargetUtils.psm1'
Import-Module $flowTargetUtilsModule -Force

function Get-DefaultMailerParamFilePath {
    [CmdletBinding()]
    param()

    $tomatoRoot = ([string]$env:TOMATO_ROOT ?? '').Trim()
    if ($tomatoRoot) {
        $fromEnv = Join-Path $tomatoRoot 'base\resources\mailer-sample.json'
        if (Test-Path -LiteralPath $fromEnv -PathType Leaf) {
            return $fromEnv
        }
    }

    return (Join-Path $PSScriptRoot '..\..\resources\mailer-sample.json')
}

function Get-DefaultMailerExecutable {
    [CmdletBinding()]
    param()

    if (Test-ExecutableAvailable -Exe 'mailer') { return 'mailer' }
    if (Test-ExecutableAvailable -Exe 'mailer.exe') { return 'mailer.exe' }

    return $null
}

function New-MailerParamFileWithContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ParamFilePath,

        [Parameter()]
        [string]$FlowName,

        [Parameter()]
        [string]$RootPath,

        [Parameter()]
        [string]$TargetPath,

        [Parameter()]
        [string]$PathType,

        [Parameter()]
        [string]$Subfolder
    )

    if (-not (Test-Path -LiteralPath $ParamFilePath -PathType Leaf)) {
        throw "Mailer parameter file not found: $ParamFilePath"
    }

    $raw = Get-Content -LiteralPath $ParamFilePath -Raw -Encoding UTF8
    if (-not $raw -or -not $raw.Trim()) {
        throw "Mailer parameter file is empty: $ParamFilePath"
    }

    $payload = $raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
    if (-not $payload) {
        throw "Mailer parameter file must contain a JSON object: $ParamFilePath"
    }

    # Resolve bodyFile relative to the sample file so execution is robust from any cwd.
    if ($payload.ContainsKey('bodyFile') -and $payload['bodyFile']) {
        $bodyFileValue = ([string]$payload['bodyFile']).Trim()
        if ($bodyFileValue) {
            $isAbsoluteBodyFile = [System.IO.Path]::IsPathRooted($bodyFileValue)
            if (-not $isAbsoluteBodyFile) {
                $paramDir = Split-Path -Parent $ParamFilePath
                $payload['bodyFile'] = [System.IO.Path]::GetFullPath((Join-Path $paramDir $bodyFileValue))
            }
        }
    }

    if (-not $payload.ContainsKey('context') -or -not $payload['context']) {
        $payload['context'] = @{}
    }
    if (-not ($payload['context'] -is [hashtable])) {
        $payload['context'] = @{}
    }
    if (-not $payload['context'].ContainsKey('variables') -or -not $payload['context']['variables']) {
        $payload['context']['variables'] = @{}
    }
    if (-not ($payload['context']['variables'] -is [hashtable])) {
        $payload['context']['variables'] = @{}
    }

    $variables = $payload['context']['variables']
    if ($FlowName) { $variables['FLOW_NAME'] = $FlowName }
    if ($RootPath) { $variables['FLOW_ROOT_PATH'] = $RootPath }
    if ($TargetPath) { $variables['FLOW_TARGET_PATH'] = $TargetPath }
    if ($PathType) { $variables['FLOW_PATH_TYPE'] = $PathType }
    if ($Subfolder) { $variables['FLOW_SUBFOLDER'] = $Subfolder }
    $variables['TOMATO_ROOT'] = ([string]$env:TOMATO_ROOT ?? '')

    $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tomato-mailer-param-{0}.json" -f ([guid]::NewGuid().ToString('N')))
    $payload | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $tempPath -Encoding UTF8

    return $tempPath
}

$tomatoRoot = ([string]$env:TOMATO_ROOT ?? '').Trim()
$customDraftScript = if ($tomatoRoot) {
    Join-Path $tomatoRoot 'automations\Create-DraftEmail.ps1'
} else {
    $null
}

if ($customDraftScript -and (Test-Path -LiteralPath $customDraftScript -PathType Leaf)) {
    Write-Host "Running custom draft automation: $customDraftScript" -ForegroundColor Yellow

    $targetPath = $Path
    if ($Path) {
        $target = Resolve-FlowTargetPath -RootPath $Path -PathType $PathType -Subfolder $Subfolder -PromptLabel 'draft email'
        if ($target.Status -eq 'Aborted') {
            Write-Host 'Draft email action aborted (ESC).' -ForegroundColor DarkYellow
            Write-Output (New-ToolResult -Status 'Aborted' -Data @{
                    FlowName = $FlowName
                    RootPath = $Path
                    PathType = $PathType
                    Action = 'Create Draft Email'
                })
            exit 0
        }

        if ($target.UsedFallback) {
            Write-Host "Using latest month folder: $($target.SubfolderName)" -ForegroundColor Gray
        }

        $targetPath = $target.TargetPath
    }

    $invokeArgs = @{}
    if ($FlowName) { $invokeArgs.FlowName = $FlowName }
    if ($targetPath) { $invokeArgs.Path = $targetPath }
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
            Path = $targetPath
            PathType = $PathType
            Script = $customDraftScript
        })
    exit 0
}

$targetPath = $Path
$targetSubfolder = $Subfolder
if ($Path) {
    $target = Resolve-FlowTargetPath -RootPath $Path -PathType $PathType -Subfolder $Subfolder -PromptLabel 'draft email'
    if ($target.Status -eq 'Aborted') {
        Write-Host 'Draft email action aborted (ESC).' -ForegroundColor DarkYellow
        Write-Output (New-ToolResult -Status 'Aborted' -Data @{
                FlowName = $FlowName
                RootPath = $Path
                PathType = $PathType
                Action = 'Create Draft Email'
            })
        exit 0
    }

    if ($target.UsedFallback) {
        Write-Host "Using latest month folder: $($target.SubfolderName)" -ForegroundColor Gray
    }

    $targetPath = $target.TargetPath
    $targetSubfolder = $target.SubfolderName
}

$mailerExe = Get-DefaultMailerExecutable
if (-not $mailerExe) {
    throw "mailer.exe is required for Create-DraftEmail. Install it (for example via ./scripts/Install-Mailer.ps1 in the Mailer project) and ensure 'mailer' is available on PATH."
}

$baseParamFile = Get-DefaultMailerParamFilePath
$effectiveParamFile = $null
$mailerOutput = @()

try {
    $effectiveParamFile = New-MailerParamFileWithContext `
        -ParamFilePath $baseParamFile `
        -FlowName $FlowName `
        -RootPath $Path `
        -TargetPath $targetPath `
        -PathType $PathType `
        -Subfolder $targetSubfolder

    Write-Host "Creating draft with mailer using: $effectiveParamFile" -ForegroundColor Yellow
    $mailerOutput = @(& $mailerExe 'draft' '--param-file' $effectiveParamFile)

    if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
        throw "mailer draft failed with exit code $LASTEXITCODE"
    }
}
finally {
    if ($effectiveParamFile -and (Test-Path -LiteralPath $effectiveParamFile -PathType Leaf)) {
        Remove-Item -LiteralPath $effectiveParamFile -Force -ErrorAction SilentlyContinue
    }
}

if ($mailerOutput -and $mailerOutput.Count -gt 0) {
    Write-Output $mailerOutput
}

Write-Output (New-ToolResult -Status 'Completed' -Data @{
        FlowName = $FlowName
        RootPath = $Path
        Path = $targetPath
        Subfolder = $targetSubfolder
        PathType = $PathType
        ParamFile = $baseParamFile
        MailerExecutable = $mailerExe
    })

exit 0
