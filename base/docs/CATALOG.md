# Base Capability Catalog

This catalog is the single reference for what the base layer provides and how to use it.

## How to read this catalog
- Scope: only capabilities implemented in the base layer.
- Paths are relative to the base folder unless noted otherwise.
- Commands are examples and should be adapted to your own entity paths.

## Runtime entrypoints

### Root app entrypoint
- File: ../Start-Main.ps1 (repo root)
- Purpose: interactive launcher for configured automations and folder previews.
- Typical usage:
  - pwsh -NoProfile -File ../Start-Main.ps1

### Configuration entrypoints
- File: ../conf/automations.json (repo root)
- Purpose: declares available automations and imports.

## Core helper modules

### helpers/AutomationConfig.psm1
- Purpose: load automation definitions and execute configured commands.
- Key exports:
  - Get-AutomationConfigPaths
  - Get-Automations
  - Invoke-AutomationCommand

### helpers/SettingsView.psm1
- Purpose: renders the Settings view used by the interactive main entrypoint.
- Key exports:
  - Show-SettingsView

## Generic utilities (utils)

### Path and directory abstraction
- File: utils/PathUtils.psm1
- Purpose: normalize local/remote path handling.
- Key exports:
  - Resolve-UnifiedPath
  - Join-UnifiedPath

- File: utils/DirectoryUtils.psm1
- Purpose: list files/folders from local or remote locations.
- Key exports:
  - Get-Items
  - Get-Files
  - Get-Folders

### Command and output utilities
- File: utils/common/CommandUtils.psm1
- Purpose: safe wrappers for external commands (especially rclone).
- Key exports:
  - Test-ExecutableAvailable
  - Assert-RcloneAvailable
  - Invoke-Rclone

- File: utils/common/ResultUtils.psm1
- Purpose: standard structured output object for script composition.
- Key exports:
  - New-ToolResult

### Interactive tooling
- File: utils/EditorUtils.psm1
- Purpose: editor selection and blocking wait behavior.
- Key exports:
  - Invoke-Editor

- File: utils/Select-ViewOption.ps1
- Purpose: generic view option selector that returns raw user selection based on consumer-defined prompt guidance, with configurable ESC behavior (`ClearInput`, `ExitView`, `GoBack`).

- File: utils/Preview-Location.ps1
- Purpose: read-only folder navigation/preview for local and remote paths.
- Typical usage:
  - pwsh -NoProfile -File ./utils/Preview-Location.ps1 -Root "gdrive:parties/acme/rapoarte"

## Tomatoflow (recommended workflow)

Tomatoflow is an opinionated workflow package that builds on the generic utilities.

Setup model:
- Base automations expose setup actions under `tomatoflow-setup`.
- Setup writes flow-specific runtime command entries in the local metadata file `%LOCALAPPDATA%/tomato/tomatoflow-meta.json`.
- Configured flows are exposed as top-level automation folders (same level as `tomatoflow-setup`).
- Runtime metadata entries contain only `alias`, `categoryPath`, and `command`.
- Script commands stored in metadata reference repository scripts via `$env:TOMATO_ROOT`.
- Root config imports that local file, so each user can provision flows without modifying repo files.

### Setup and runtime automations
- File: tomatoflow/configure/Initialize-Tomatoflow.ps1
- Purpose: creates or updates one flow definition in local tomatoflow metadata, including per-flow commands for monthly run, preview, ensure month folder, label, archive, draft email, and conclude month folder.

- File: tomatoflow/configure/List-Tomatoflows.ps1
- Purpose: lists flows currently configured in local tomatoflow metadata.

- File: tomatoflow/configure/Remove-Tomatoflow.ps1
- Purpose: removes one flow definition (and its managed command entries) from local metadata.

- File: tomatoflow/automations/Run-MonthlyFlow.ps1
- Purpose: runs the unified monthly flow for a configured storage path.

- File: tomatoflow/automations/Create-DraftEmail.ps1
- Purpose: runs draft-email automation for a configured flow, with optional repository-level override at TOMATO_ROOT/automations/Create-DraftEmail.ps1.

- File: tomatoflow/automations/Conclude-MonthFolder.ps1
- Purpose: resolves target subfolder for conclude action (ESC-aware prompt, latest-month fallback), then concludes that month folder.

- File: tomatoflow/automations/modules/FlowTargetUtils.psm1
- Purpose: shared target-folder resolution for flow automations, including latest-month fallback and ESC-aware prompt input.

- File: tomatoflow/configure/modules/FlowConfigUtils.psm1
- Purpose: shared flow configuration helpers for managed alias set and categoryPath parsing.

### Tomatoflow building-block scripts
- File: tomatoflow/automations/scripts/Ensure-NewMonthFolder.ps1
- Purpose: creates the next missing month folder based on existing month folders.
- Typical usage:
  - pwsh -NoProfile -File ./tomatoflow/automations/scripts/Ensure-NewMonthFolder.ps1 -Path "gdrive:parties/entity/rapoarte"

- File: tomatoflow/automations/scripts/Create-MonthlyReport.ps1
- Purpose: creates next month folder and copies template files.
- Typical usage:
  - pwsh -NoProfile -File ./tomatoflow/automations/scripts/Create-MonthlyReport.ps1 -Path "gdrive:parties/entity/rapoarte"

- File: tomatoflow/automations/scripts/Conclude-MonthFolder.ps1
- Purpose: removes underscore prefix from the last worked month folder (or an explicit target folder when provided).
- Typical usage:
  - pwsh -NoProfile -File ./tomatoflow/automations/scripts/Conclude-MonthFolder.ps1 -Path "gdrive:parties/entity/rapoarte"

- File: tomatoflow/automations/scripts/Label-Files.ps1
- Purpose: labels files (for example INVOICE/EXPENSE/BALANCE) for later grouping.
- Typical usage:
  - pwsh -NoProfile -File ./tomatoflow/automations/scripts/Label-Files.ps1 -Path "gdrive:parties/entity/rapoarte/_current-month"

- File: tomatoflow/automations/scripts/Archive-ByLabel.ps1
- Purpose: creates one archive per label and uploads/copies output.
- Typical usage:
  - pwsh -NoProfile -File ./tomatoflow/automations/scripts/Archive-ByLabel.ps1 -Path "gdrive:parties/entity/rapoarte/_current-month"

- File: tomatoflow/automations/scripts/Copy-ToMonthFolder.ps1
- Purpose: copies month assets between source/destination paths.
- Typical usage:
  - pwsh -NoProfile -File ./tomatoflow/automations/scripts/Copy-ToMonthFolder.ps1 -SourcePath "..." -DestinationPath "..."

- File: tomatoflow/automations/scripts/Get-LastMonth.ps1
- Purpose: returns latest month tag from a list of month names.
- Typical usage:
  - pwsh -NoProfile -File ./tomatoflow/automations/scripts/Get-LastMonth.ps1 -Values @('jan-2026','_feb-2026') -SkipInvalid

### Tomatoflow reusable modules
- File: tomatoflow/automations/scripts/modules/MonthUtils.psm1
- Purpose: month parsing and next-missing-month calculations.

- File: tomatoflow/automations/scripts/modules/LabelUtils.psm1
- Purpose: label parsing, selector generation, unique name rules.

- File: tomatoflow/automations/scripts/modules/DriveUtils.psm1
- Purpose: Drive metadata helpers and browser URL generation.

### Tomatoflow automations menu
- File: tomatoflow/automations.json
- Purpose: exposes setup-first automations; flow-specific command entries are provisioned locally at runtime.

## Maintenance rule

When adding or changing any base capability:
1. Update this catalog.
2. Update base/README.md if overview, scope, or package boundaries changed.
