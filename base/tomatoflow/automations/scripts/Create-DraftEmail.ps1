# -----------------------------------------------------------------------------
# Create-DraftEmail.ps1
# -----------------------------------------------------------------------------
# Non-interactive draft-email implementation for Tomatoflow.
#
# Expected inputs:
#   - Path points to the already resolved month folder target.
#
# Behavior:
#   - Uses `mailer draft --param-file` with base/resources/mailer-sample.json.
#   - Enriches param-file context.variables with TOMATO_ROOT.
#   - Supports interactive attachment selection from target folder files.
# -----------------------------------------------------------------------------
[CmdletBinding()]
param(
    [Parameter()]
    [string]$FlowName,

    [Parameter(Mandatory = $true)]
    [string]$Path,

    [Parameter()]
    [ValidateSet('Auto', 'Local', 'Remote')]
    [string]$PathType = 'Auto',

    [Parameter()]
    [object]$DefaultAttachmentPatterns
)

$ErrorActionPreference = 'Stop'

$commandUtilsModule = Join-Path $PSScriptRoot '..\..\..\utils\common\CommandUtils.psm1'
Import-Module $commandUtilsModule -Force

$pathUtilsModule = Join-Path $PSScriptRoot '..\..\..\utils\PathUtils.psm1'
Import-Module $pathUtilsModule -Force

$directoryUtilsModule = Join-Path $PSScriptRoot '..\..\..\utils\DirectoryUtils.psm1'
Import-Module $directoryUtilsModule -Force

$pathPatternUtilsModule = Join-Path $PSScriptRoot '..\..\..\utils\common\PathPatternUtils.psm1'
Import-Module $pathPatternUtilsModule -Force

$editorModule = Join-Path $PSScriptRoot '..\..\..\utils\EditorUtils.psm1'
Import-Module $editorModule -Force

$todoEditorUtilsModule = Join-Path $PSScriptRoot '..\..\..\utils\common\TodoEditorUtils.psm1'
Import-Module $todoEditorUtilsModule -Force

$resultUtilsModule = Join-Path $PSScriptRoot '..\..\..\utils\common\ResultUtils.psm1'
Import-Module $resultUtilsModule -Force

$flowTargetUtilsModule = Join-Path $PSScriptRoot '..\modules\FlowTargetUtils.psm1'
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

    return (Join-Path $PSScriptRoot '..\..\..\resources\mailer-sample.json')
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

    function Get-AttachmentScope {
        param([Parameter(Mandatory = $true)][string]$RelativePath)

        if ($RelativePath -match '^(?i:archives?/)') {
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
            $relativePath = (([System.IO.Path]::GetRelativePath($targetInfo.LocalPath, $file.FullName) ?? '').Trim().Replace('\\', '/').TrimStart('/'))
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

            $relativePath = (($entry ?? '').Trim().Replace('\\', '/').TrimStart('/'))
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
        [object[]]$Items,

        [Parameter()]
        [AllowEmptyCollection()]
        [string[]]$SelectedRelativePaths = @()
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

    $selectedLookup = @{}
    foreach ($p in @($SelectedRelativePaths)) {
        $key = ([string]$p ?? '').Trim().Replace('\\', '/').TrimStart('/')
        if ($key) {
            $selectedLookup[$key] = $true
        }
    }

    foreach ($it in ($Items | Sort-Object RelativePath)) {
        $relativePath = ([string]$it.RelativePath ?? '').Trim().Replace('\\', '/').TrimStart('/')
        $escaped = $relativePath.Replace('\\', '\\\\').Replace('"', '\"')

        $isScopeDefaultSelected = (([string]$it.Scope ?? '').Trim().ToLowerInvariant() -eq 'archives')
        $isExplicitlySelected = $selectedLookup.ContainsKey($relativePath)

        # Keep scope behavior as baseline and overlay explicit selections from pattern matching.
        $defaultAction = if ($isScopeDefaultSelected -or $isExplicitlySelected) { 'y' } else { 'n' }

        $null = $sb.AppendLine($defaultAction + ' "' + $escaped + '"')
    }

    return $sb.ToString()
}

function Read-ConfirmationChoice {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PromptText,

        [Parameter(Mandatory = $true)]
        [string[]]$Choices,

        [Parameter(Mandatory = $true)]
        [string]$DefaultChoice
    )

    $normalizedChoices = @($Choices | ForEach-Object { ([string]$_ ?? '').Trim() } | Where-Object { $_ })
    if (-not $normalizedChoices -or $normalizedChoices.Count -eq 0) {
        throw 'Read-ConfirmationChoice requires at least one choice.'
    }

    $defaultCanonical = ($DefaultChoice ?? '').Trim()
    if ($normalizedChoices -notcontains $defaultCanonical) {
        throw "Default choice '$DefaultChoice' is not in choices list."
    }

    $byLower = @{}
    foreach ($choice in $normalizedChoices) {
        $choiceLower = $choice.ToLowerInvariant()
        if (-not $byLower.ContainsKey($choiceLower)) {
            $byLower[$choiceLower] = $choice
        }
    }

    $charCounts = @{}
    foreach ($choice in $normalizedChoices) {
        $key = $choice.Substring(0, 1).ToLowerInvariant()
        if (-not $charCounts.ContainsKey($key)) {
            $charCounts[$key] = 0
        }
        $charCounts[$key]++
    }

    $shortcuts = @{}
    foreach ($choice in $normalizedChoices) {
        $key = $choice.Substring(0, 1).ToLowerInvariant()
        if ($charCounts[$key] -eq 1) {
            $shortcuts[$key] = $choice
        }
    }

    $optionsText = ($normalizedChoices -join '/')
    $prompt = "{0} [{1}] (default: {2})" -f $PromptText, $optionsText, $defaultCanonical

    while ($true) {
        $response = Read-InputWithEsc -Prompt $prompt
        if ($response.Status -eq 'Escaped') {
            return [pscustomobject]@{ Status = 'Aborted'; Choice = $null }
        }

        $raw = ([string]$response.Value ?? '').Trim()
        if (-not $raw) {
            return [pscustomobject]@{ Status = 'Selected'; Choice = $defaultCanonical }
        }

        $value = $raw.ToLowerInvariant()

        if ($byLower.ContainsKey($value)) {
            return [pscustomobject]@{ Status = 'Selected'; Choice = $byLower[$value] }
        }

        if ($shortcuts.ContainsKey($value)) {
            return [pscustomobject]@{ Status = 'Selected'; Choice = $shortcuts[$value] }
        }

        Write-Host "Unrecognized input '$raw'. Allowed values: $optionsText" -ForegroundColor DarkYellow
    }
}

function ConvertTo-PatternArray {
    [CmdletBinding()]
    param([Parameter()][object]$Value)

    if ($null -eq $Value) { return @() }

    if ($Value -is [string]) {
        $text = ([string]$Value ?? '').Trim()
        if (-not $text) { return @() }
        return @($text)
    }

    if ($Value -is [array]) {
        return @(
            $Value |
                ForEach-Object { ([string]$_ ?? '').Trim() } |
                Where-Object { $_ }
        )
    }

    $single = ([string]$Value ?? '').Trim()
    if (-not $single) { return @() }
    return @($single)
}

function Resolve-AttachmentPatternSpec {
    [CmdletBinding()]
    param([Parameter()][object]$PatternSpec)

    if ($null -eq $PatternSpec) {
        return [pscustomobject]@{ Include = @(); Exclude = @() }
    }

    if ($PatternSpec -is [string]) {
        $includeSingle = ConvertTo-PatternArray -Value $PatternSpec
        return [pscustomobject]@{ Include = @($includeSingle); Exclude = @() }
    }

    $includePatterns = @()
    $excludePatterns = @()

    $hasInclude = $PatternSpec.PSObject.Properties.Name -contains 'include'
    $hasExclude = $PatternSpec.PSObject.Properties.Name -contains 'exclude'
    if ($hasInclude -or $hasExclude) {
        if ($hasInclude) {
            $includePatterns = ConvertTo-PatternArray -Value $PatternSpec.include
        }
        if ($hasExclude) {
            $excludePatterns = ConvertTo-PatternArray -Value $PatternSpec.exclude
        }

        return [pscustomobject]@{ Include = @($includePatterns); Exclude = @($excludePatterns) }
    }

    $asText = ([string]$PatternSpec ?? '').Trim()
    if ($asText) {
        return [pscustomobject]@{ Include = @($asText); Exclude = @() }
    }

    return [pscustomobject]@{ Include = @(); Exclude = @() }
}

function Read-AttachmentTodo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TodoPath
    )

    $parsed = Read-StructuredTodo -TodoPath $TodoPath -ExpectedUsage '<y|n> <relative_path>' -NameLabel 'relative path' -LowercaseAction -EmptyMode 'reset'
    if ($parsed.Mode -ne 'apply') {
        return $parsed
    }

    $ops = @(
        @($parsed.Ops) |
            ForEach-Object {
                [pscustomobject]@{
                    Action = [string]$_.Action
                    RelativePath = [string]$_.Name
                }
            }
    )

    return [pscustomobject]@{ Mode = 'apply'; Ops = $ops }
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

    Write-TodoErrorHeader -TodoPath $TodoPath -ErrorMessage $ErrorMessage
}

function Edit-AttachmentSelection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Items,

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$SelectedItems = @()
    )

    $tmpTodo = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ("tomato-draft-attachments-{0}.todo" -f ([guid]::NewGuid().ToString('N')))
    $resetCount = 0
    $todoInitialized = $false
    $regenerateTodo = $true

    $selectedRelativePaths = @(
        @($SelectedItems) |
            ForEach-Object { ([string]$_.RelativePath ?? '').Trim() } |
            Where-Object { $_ }
    )

    try {
        while ($true) {
            if ($regenerateTodo -or -not $todoInitialized) {
                Set-Content -LiteralPath $tmpTodo -Value (New-AttachmentTodoText -Items $Items -SelectedRelativePaths $selectedRelativePaths) -Encoding UTF8
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
        [string]$TargetPath
    )

    if (-not $SelectedItems -or $SelectedItems.Count -eq 0) {
        return [pscustomobject]@{
            Attachments = @()
            TempDir = $null
        }
    }

    $tempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("tomato-draft-attach-{0}" -f ([guid]::NewGuid().ToString('N')))
    New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

    $archiveRoots = @(
        $SelectedItems |
            Where-Object { $_.Scope -eq 'archives' } |
            ForEach-Object {
                $rel = ([string]$_.RelativePath ?? '').Replace('\\', '/').TrimStart('/')
                if (-not $rel) { return $null }
                return ($rel.Split('/')[0])
            } |
            Where-Object { $_ } |
            Select-Object -Unique
    )

    foreach ($archiveRoot in $archiveRoots) {
        $remoteArchivePath = Join-UnifiedPath -Base $TargetPath -Child $archiveRoot -PathType 'Remote'
        $localArchiveDir = Join-Path $tempDir $archiveRoot
        New-Item -ItemType Directory -Path $localArchiveDir -Force | Out-Null
        Invoke-Rclone -Arguments @('copy', $remoteArchivePath, $localArchiveDir) -ErrorMessage "Failed to download remote archive folder '$remoteArchivePath'." | Out-Null
    }

    $attachments = @()
    foreach ($item in $SelectedItems) {
        if ($item.Scope -eq 'archives') {
            $relativePath = ([string]$item.RelativePath ?? '').Replace('/', [System.IO.Path]::DirectorySeparatorChar)
            $localPath = Join-Path $tempDir $relativePath
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
        [string]$PathType = 'Auto',

        [Parameter()]
        [object]$DefaultPatterns
    )

    $discovery = Get-AttachmentCandidates -TargetPath $TargetPath -PathType $PathType
    $items = @($discovery.Items)
    if (-not $items -or $items.Count -eq 0) {
        Write-Host 'No files found in selected month folder or subfolders to attach.' -ForegroundColor DarkYellow
        return [pscustomobject]@{ Status = 'Empty'; Attachments = @(); TempDir = $null; Selected = @() }
    }
	
    $patternSpec = Resolve-AttachmentPatternSpec -PatternSpec $DefaultPatterns
    $selected = @()
	
    if ($patternSpec.Include.Count -gt 0) {
        $candidatePaths = @($items | ForEach-Object { [string]$_.RelativePath })
        $selectedRelativePaths = @(
            Select-PathsByPattern -Paths $candidatePaths -IncludePatterns @($patternSpec.Include) -ExcludePatterns @($patternSpec.Exclude)
        )
		
        if ($selectedRelativePaths.Count -gt 0) {
            $selectedLookup = @{}
            foreach ($p in $selectedRelativePaths) {
                $selectedLookup[[string]$p] = $true
            }

            $selected = @(
                $items |
                    Where-Object { $selectedLookup.ContainsKey([string]$_.RelativePath) }
            )
        }
    }
	
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

        $confirm = Read-ConfirmationChoice -PromptText 'Proceed with these attachments?' -Choices @('Yes', 'No', 'Edit', 'Abort') -DefaultChoice 'Yes'
        if ($confirm.Status -eq 'Aborted') {
            return [pscustomobject]@{ Status = 'Aborted'; Attachments = @(); TempDir = $null; Selected = @() }
        }

        $choice = [string]$confirm.Choice
        if ($choice -eq 'Yes') {
            break
        }

        if ($choice -eq 'No') {
            $selected = @()
            break
        }

        if ($choice -eq 'Edit') {
            $editResult = Edit-AttachmentSelection -Items $items -SelectedItems $selected
            if ($editResult.Status -eq 'Aborted') {
                return [pscustomobject]@{ Status = 'Aborted'; Attachments = @(); TempDir = $null; Selected = @() }
            }

            $selected = @($editResult.Selected)
            break
        }

        if ($choice -eq 'Abort') {
            return [pscustomobject]@{ Status = 'Aborted'; Attachments = @(); TempDir = $null; Selected = @() }
        }
    }

    if ($discovery.PathInfo.PathType -eq 'Remote') {
        $resolved = Resolve-RemoteAttachmentPaths -SelectedItems $selected -TargetPath $discovery.PathInfo.Normalized
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
        [string]$TargetPath,

        [Parameter()]
        [string]$PathType
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
    $variables['TOMATO_ROOT'] = ([string]$env:TOMATO_ROOT ?? '')

    $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) ("tomato-mailer-param-{0}.json" -f ([guid]::NewGuid().ToString('N')))
    $payload | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $tempPath -Encoding UTF8

    return $tempPath
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
$derivedSubfolder = ''
if ($Path) {
    $derivedSubfolder = ([string](Split-Path -Leaf $Path) ?? '').Trim()
}

try {
    $effectiveParamFile = New-MailerParamFileWithContext `
        -ParamFilePath $baseParamFile `
        -FlowName $FlowName `
        -TargetPath $Path `
        -PathType $PathType

    $attachmentSelection = Select-Attachments -TargetPath $Path -PathType $PathType -DefaultPatterns $DefaultAttachmentPatterns
    if ($attachmentSelection.Status -eq 'Aborted') {
        Write-Host 'Draft email action aborted (ESC).' -ForegroundColor DarkYellow
        Write-Output (New-ToolResult -Status 'Aborted' -Data @{
                FlowName = $FlowName
                Path = $Path
                Subfolder = $derivedSubfolder
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
        Path = $Path
        Subfolder = $derivedSubfolder
        PathType = $PathType
        AttachmentCount = if ($attachmentSelection) { @($attachmentSelection.Attachments).Count } else { 0 }
        ParamFile = $baseParamFile
        MailerExecutable = $mailerExe
    })

exit 0
