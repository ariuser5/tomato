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

$pathUtilsModule = Join-Path $PSScriptRoot '..\..\utils\PathUtils.psm1'
Import-Module $pathUtilsModule -Force

$directoryUtilsModule = Join-Path $PSScriptRoot '..\..\utils\DirectoryUtils.psm1'
Import-Module $directoryUtilsModule -Force

$editorModule = Join-Path $PSScriptRoot '..\..\utils\EditorUtils.psm1'
Import-Module $editorModule -Force

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

function Get-AttachmentCandidates {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetPath,

        [Parameter()]
        [ValidateSet('Auto', 'Local', 'Remote')]
        [string]$PathType = 'Auto'
    )

    $targetInfo = Resolve-UnifiedPath -Path $TargetPath -PathType $PathType

    function Normalize-RelativeAttachmentPath {
        param([Parameter(Mandatory = $true)][string]$PathValue)

        return (($PathValue ?? '').Trim().Replace('\', '/').TrimStart('/'))
    }

    function Get-AttachmentScope {
        param([Parameter(Mandatory = $true)][string]$RelativePath)

        if ($RelativePath -match '^(?i:archives/)') {
            return 'archives'
        }

        return 'current'
    }

    $candidates = @()
    if ($targetInfo.PathType -eq 'Local') {
        if (-not (Test-Path -LiteralPath $targetInfo.LocalPath -PathType Container)) {
            return [pscustomobject]@{ PathInfo = $targetInfo; ArchivesPath = (Join-UnifiedPath -Base $targetInfo.Normalized -Child 'archives' -PathType $targetInfo.PathType); Items = @() }
        }

        $localFiles = @(Get-ChildItem -LiteralPath $targetInfo.LocalPath -File -Recurse -ErrorAction Stop)
        foreach ($file in $localFiles) {
            $relativePath = Normalize-RelativeAttachmentPath -PathValue ([System.IO.Path]::GetRelativePath($targetInfo.LocalPath, $file.FullName))
            $candidates += [pscustomobject]@{
                DisplayName = $relativePath
                RelativePath = $relativePath
                SourcePath = $file.FullName
                Scope = Get-AttachmentScope -RelativePath $relativePath
                PathType = $targetInfo.PathType
                LocalPath = $file.FullName
            }
        }
    }
    else {
        Assert-RcloneAvailable
        $remoteFiles = @(Invoke-Rclone -Arguments @('lsf', $targetInfo.Normalized, '-R', '--files-only') -ErrorMessage "Failed to list remote files under '$($targetInfo.Normalized)'.")
        foreach ($raw in $remoteFiles) {
            $entry = ([string]$raw ?? '').Trim()
            if (-not $entry) { continue }

            $relativePath = Normalize-RelativeAttachmentPath -PathValue $entry
            $sourcePath = Join-UnifiedPath -Base $targetInfo.Normalized -Child $relativePath -PathType $targetInfo.PathType
            $candidates += [pscustomobject]@{
                DisplayName = $relativePath
                RelativePath = $relativePath
                SourcePath = $sourcePath
                Scope = Get-AttachmentScope -RelativePath $relativePath
                PathType = $targetInfo.PathType
                LocalPath = $null
            }
        }
    }

    $archivesPath = Join-UnifiedPath -Base $targetInfo.Normalized -Child 'archives' -PathType $targetInfo.PathType

    return [pscustomobject]@{
        PathInfo = $targetInfo
        ArchivesPath = $archivesPath
        Items = @($candidates | Sort-Object RelativePath)
    }
}

function New-AttachmentTodoText {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Items
    )

    $sb = New-Object System.Text.StringBuilder
    $null = $sb.AppendLine('# tomato: Create-DraftEmail attachment selection todo')
    $null = $sb.AppendLine('#')
    $null = $sb.AppendLine('# Commands:')
    $null = $sb.AppendLine('#   y <relative_path>   = include file as attachment')
    $null = $sb.AppendLine('#   n <relative_path>   = exclude file from attachments')
    $null = $sb.AppendLine('#')
    $null = $sb.AppendLine('# Special:')
    $null = $sb.AppendLine('#   abort = abort draft email action')
    $null = $sb.AppendLine('#   reset = regenerate defaults (all y) and reopen editor')
    $null = $sb.AppendLine('#')

    foreach ($it in ($Items | Sort-Object RelativePath)) {
        $escaped = ([string]$it.RelativePath).Replace('\\', '\\\\').Replace('"', '\"')
        $defaultAction = if (([string]$it.Scope) -eq 'archives') { 'y' } else { 'n' }
        $null = $sb.AppendLine($defaultAction + ' "' + $escaped + '"')
    }

    return $sb.ToString()
}

function Read-AttachmentTodo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TodoPath
    )

    $lines = Get-Content -LiteralPath $TodoPath -ErrorAction Stop
    $ops = New-Object System.Collections.Generic.List[object]

    foreach ($raw in $lines) {
        $line = ([string]$raw ?? '').Trim()
        if (-not $line -or $line.StartsWith('#')) { continue }

        if ($line -ieq 'abort') { return [pscustomobject]@{ Mode = 'abort' } }
        if ($line -ieq 'reset') { return [pscustomobject]@{ Mode = 'reset' } }

        if ($line -notmatch '^(?<action>\S+)\s+(?<name>.+)$') {
            throw "Invalid todo line: '$line' (expected: <y|n> <relative_path>)"
        }

        $action = $Matches['action'].Trim().ToLowerInvariant()
        $nameRaw = $Matches['name'].Trim()
        if (-not $nameRaw) {
            throw "Invalid todo line: '$line' (missing relative path)"
        }

        $name = $null
        if ($nameRaw.StartsWith('"')) {
            if ($nameRaw -notmatch '^"(?<inner>(?:\\.|[^"\\])*)"\s*$') {
                throw "Invalid quoted relative path in todo line: '$line'"
            }

            $inner = $Matches['inner']
            $sbName = New-Object System.Text.StringBuilder
            for ($i = 0; $i -lt $inner.Length; $i++) {
                $ch = $inner[$i]
                if ($ch -eq '\\') {
                    if ($i + 1 -ge $inner.Length) { throw "Invalid escape sequence in todo line: '$line'" }
                    $next = $inner[$i + 1]
                    switch ($next) {
                        '"' { $null = $sbName.Append('"') }
                        '\\' { $null = $sbName.Append('\\') }
                        default { $null = $sbName.Append($next) }
                    }
                    $i++
                    continue
                }
                $null = $sbName.Append($ch)
            }
            $name = $sbName.ToString()
        }
        else {
            $name = $nameRaw
        }

        $ops.Add([pscustomobject]@{ Action = $action; RelativePath = $name }) | Out-Null
    }

    return [pscustomobject]@{ Mode = 'apply'; Ops = @($ops.ToArray()) }
}

function Test-AttachmentTodoOps {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Ops,

        [Parameter(Mandatory = $true)]
        [hashtable]$ItemByRelativePath
    )

    foreach ($op in $Ops) {
        if (-not ($op.Action -in @('y', 'n'))) {
            return [pscustomobject]@{ IsValid = $false; Error = "Unknown action '$($op.Action)' for '$($op.RelativePath)'. Allowed: y or n." }
        }

        if (-not $ItemByRelativePath.ContainsKey($op.RelativePath)) {
            return [pscustomobject]@{ IsValid = $false; Error = "Todo references unknown file '$($op.RelativePath)'." }
        }
    }

    return [pscustomobject]@{ IsValid = $true }
}

function Write-AttachmentTodoErrorHeader {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TodoPath,

        [Parameter(Mandatory = $true)]
        [string]$ErrorMessage
    )

    $lines = Get-Content -LiteralPath $TodoPath -ErrorAction Stop

    $begin = '# ERROR-BEGIN'
    $end = '# ERROR-END'
    $beginIndex = -1
    $endIndex = -1

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($beginIndex -lt 0 -and $lines[$i].Trim() -eq $begin) { $beginIndex = $i; continue }
        if ($beginIndex -ge 0 -and $lines[$i].Trim() -eq $end) { $endIndex = $i; break }
    }

    if ($beginIndex -ge 0 -and $endIndex -ge $beginIndex) {
        if ($beginIndex -eq 0) {
            $lines = $lines[($endIndex + 1)..($lines.Count - 1)]
        }
        else {
            $before = $lines[0..($beginIndex - 1)]
            $after = if ($endIndex + 1 -le ($lines.Count - 1)) { $lines[($endIndex + 1)..($lines.Count - 1)] } else { @() }
            $lines = @($before + $after)
        }
    }

    $header = @(
        $begin,
        "# ERROR: $ErrorMessage",
        '# Fix the todo and save+close to continue.',
        $end,
        '#'
    )

    Set-Content -LiteralPath $TodoPath -Value ($header + $lines) -Encoding UTF8
}

function Edit-AttachmentSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Items
    )

    $tmpTodo = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("tomato-draft-attachments-{0}.todo" -f ([guid]::NewGuid().ToString('N')))
    $resetCount = 0
    $todoInitialized = $false
    $regenerateTodo = $true

    try {
        while ($true) {
            if ($regenerateTodo -or -not $todoInitialized) {
                Set-Content -LiteralPath $tmpTodo -Value (New-AttachmentTodoText -Items $Items) -Encoding UTF8
                $todoInitialized = $true
                $regenerateTodo = $false
            }

            $editResult = Invoke-Editor -FilePath $tmpTodo
            if ($editResult -and $editResult.Mode -eq 'abort') {
                return [pscustomobject]@{ Status = 'Aborted'; Selected = @() }
            }

            $parsed = Read-AttachmentTodo -TodoPath $tmpTodo
            if ($parsed.Mode -eq 'abort') {
                return [pscustomobject]@{ Status = 'Aborted'; Selected = @() }
            }

            if ($parsed.Mode -eq 'reset') {
                $resetCount++
                if ($resetCount -ge 5) {
                    throw 'Too many resets; exiting.'
                }

                $regenerateTodo = $true
                continue
            }

            $ops = if ($null -eq $parsed.Ops) { @() } else { @($parsed.Ops) }
            if (-not $ops -or $ops.Count -eq 0) {
                Write-AttachmentTodoErrorHeader -TodoPath $tmpTodo -ErrorMessage "Todo is empty. Add at least one action line or write 'abort'."
                continue
            }

            $itemByRelativePath = @{}
            foreach ($it in $Items) {
                $itemByRelativePath[[string]$it.RelativePath] = $it
            }

            $validation = Test-AttachmentTodoOps -Ops $ops -ItemByRelativePath $itemByRelativePath
            if (-not $validation.IsValid) {
                Write-AttachmentTodoErrorHeader -TodoPath $tmpTodo -ErrorMessage $validation.Error
                continue
            }

            $selected = @()
            foreach ($op in $ops) {
                if ($op.Action -eq 'y') {
                    $selected += $itemByRelativePath[[string]$op.RelativePath]
                }
            }

            return [pscustomobject]@{ Status = 'Selected'; Selected = @($selected) }
        }
    }
    finally {
        if (Test-Path -LiteralPath $tmpTodo -PathType Leaf) {
            Remove-Item -LiteralPath $tmpTodo -ErrorAction SilentlyContinue
        }
    }
}

function Resolve-RemoteAttachmentPaths {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$SelectedItems,

        [Parameter(Mandatory = $true)]
        [string]$ArchivesPath
    )

    if (-not $SelectedItems -or $SelectedItems.Count -eq 0) {
        return [pscustomobject]@{
            Attachments = @()
            TempDir = $null
        }
    }

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tomato-draft-attach-{0}" -f ([guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    $localArchiveDir = Join-Path $tempDir 'archives'
    $needsArchives = @($SelectedItems | Where-Object { $_.Scope -eq 'archives' }).Count -gt 0
    if ($needsArchives) {
        New-Item -ItemType Directory -Path $localArchiveDir -Force | Out-Null
        Invoke-Rclone -Arguments @('copy', $ArchivesPath, $localArchiveDir) -ErrorMessage "Failed to download remote archives folder '$ArchivesPath'." | Out-Null
    }

    $attachments = @()
    foreach ($item in $SelectedItems) {
        if ($item.Scope -eq 'archives') {
            $localPath = Join-Path $localArchiveDir ([System.IO.Path]::GetFileName([string]$item.SourcePath))
            if (-not (Test-Path -LiteralPath $localPath -PathType Leaf)) {
                throw "Expected downloaded archive file not found: $localPath"
            }

            $attachments += $localPath
            continue
        }

        $relativePath = ([string]$item.RelativePath ?? '').Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        $localPath = Join-Path $tempDir $relativePath
        $localParent = Split-Path -Parent $localPath
        if ($localParent -and -not (Test-Path -LiteralPath $localParent -PathType Container)) {
            New-Item -ItemType Directory -Path $localParent -Force | Out-Null
        }

        Invoke-Rclone -Arguments @('copyto', [string]$item.SourcePath, $localPath) -ErrorMessage "Failed to download remote file '$($item.SourcePath)'." | Out-Null
        $attachments += $localPath
    }

    return [pscustomobject]@{
        Attachments = @($attachments)
        TempDir = $tempDir
    }
}

function Select-Attachments {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TargetPath,

        [Parameter()]
        [ValidateSet('Auto', 'Local', 'Remote')]
        [string]$PathType = 'Auto'
    )

    $discovery = Get-AttachmentCandidates -TargetPath $TargetPath -PathType $PathType
    $items = @($discovery.Items)
    if (-not $items -or $items.Count -eq 0) {
        Write-Host 'No files found in selected month folder or subfolders to attach.' -ForegroundColor DarkYellow
        return [pscustomobject]@{ Status = 'Empty'; Attachments = @(); TempDir = $null; Selected = @() }
    }

    $selected = @($items | Where-Object { ([string]$_.Scope) -eq 'archives' })

    while ($true) {
        Write-Host 'Files currently selected for attachment:' -ForegroundColor Cyan
        if ($selected.Count -eq 0) {
            Write-Host '- <none>' -ForegroundColor DarkGray
        }
        else {
            foreach ($item in @($selected | Sort-Object RelativePath)) {
                Write-Host ("- {0}" -f $item.RelativePath) -ForegroundColor Gray
            }
        }

        $confirm = Read-InputWithEsc -Prompt "Proceed with these attachments? [Y/n/edit/abort]"
        if ($confirm.Status -eq 'Escaped') {
            return [pscustomobject]@{ Status = 'Aborted'; Attachments = @(); TempDir = $null; Selected = @() }
        }

        $choice = ([string]$confirm.Value ?? '').Trim().ToLowerInvariant()
        if (-not $choice -or $choice -in @('y', 'yes')) {
            break
        }

        if ($choice -in @('n', 'no')) {
            $selected = @()
            break
        }

        if ($choice -eq 'edit') {
            $editResult = Edit-AttachmentSelection -Items $items
            if ($editResult.Status -eq 'Aborted') {
                return [pscustomobject]@{ Status = 'Aborted'; Attachments = @(); TempDir = $null; Selected = @() }
            }

            $selected = @($editResult.Selected)
            break
        }

        if ($choice -eq 'abort') {
            return [pscustomobject]@{ Status = 'Aborted'; Attachments = @(); TempDir = $null; Selected = @() }
        }

        Write-Host "Unrecognized input '$choice'. Use Y, n, edit, or abort." -ForegroundColor DarkYellow
    }

    if ($discovery.PathInfo.PathType -eq 'Remote') {
        $resolved = Resolve-RemoteAttachmentPaths -SelectedItems $selected -ArchivesPath $discovery.ArchivesPath
        return [pscustomobject]@{
            Status = if ($selected.Count -gt 0) { 'Selected' } else { 'NoneSelected' }
            Attachments = @($resolved.Attachments)
            TempDir = $resolved.TempDir
            Selected = @($selected)
        }
    }

    return [pscustomobject]@{
        Status = if ($selected.Count -gt 0) { 'Selected' } else { 'NoneSelected' }
        Attachments = @($selected | ForEach-Object { [string]$_.LocalPath })
        TempDir = $null
        Selected = @($selected)
    }
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
$attachmentSelection = $null
$attachmentTempDir = $null
$mailerArgs = @()

try {
    $effectiveParamFile = New-MailerParamFileWithContext `
        -ParamFilePath $baseParamFile `
        -FlowName $FlowName `
        -RootPath $Path `
        -TargetPath $targetPath `
        -PathType $PathType `
        -Subfolder $targetSubfolder

    $attachmentSelection = Select-Attachments -TargetPath $targetPath -PathType $PathType
    if ($attachmentSelection.Status -eq 'Aborted') {
        Write-Host 'Draft email action aborted (ESC).' -ForegroundColor DarkYellow
        Write-Output (New-ToolResult -Status 'Aborted' -Data @{
                FlowName = $FlowName
                RootPath = $Path
                Path = $targetPath
                Subfolder = $targetSubfolder
                PathType = $PathType
                Action = 'Create Draft Email'
            })
        exit 0
    }

    if ($attachmentSelection.TempDir) {
        $attachmentTempDir = $attachmentSelection.TempDir
    }

    $mailerArgs = @('draft', '--param-file', $effectiveParamFile)
    foreach ($attachPath in @($attachmentSelection.Attachments)) {
        $mailerArgs += @('--attach', [string]$attachPath)
    }

    Write-Host "Creating draft with mailer using: $effectiveParamFile" -ForegroundColor Yellow
    if ($attachmentSelection.Attachments.Count -gt 0) {
        Write-Host ("Attachments selected: {0}" -f $attachmentSelection.Attachments.Count) -ForegroundColor Gray
    }

    $mailerOutput = @(& $mailerExe @mailerArgs)

    if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
        throw "mailer draft failed with exit code $LASTEXITCODE"
    }
}
finally {
    if ($effectiveParamFile -and (Test-Path -LiteralPath $effectiveParamFile -PathType Leaf)) {
        Remove-Item -LiteralPath $effectiveParamFile -Force -ErrorAction SilentlyContinue
    }

    if ($attachmentTempDir -and (Test-Path -LiteralPath $attachmentTempDir -PathType Container)) {
        Remove-Item -LiteralPath $attachmentTempDir -Recurse -Force -ErrorAction SilentlyContinue
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
        AttachmentCount = if ($attachmentSelection) { @($attachmentSelection.Attachments).Count } else { 0 }
        ParamFile = $baseParamFile
        MailerExecutable = $mailerExe
    })

exit 0
