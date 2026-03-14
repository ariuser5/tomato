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
- File: ../conf/parties.json (repo root)
- Purpose: declares parties/entities with their base locations.

## Core helper modules

### helpers/AutomationConfig.psm1
- Purpose: load automation definitions and execute configured commands.
- Key exports:
  - Get-AutomationConfigPaths
  - Get-Automations
  - Invoke-AutomationCommand

### helpers/EntityConfig.psm1
- Purpose: load and merge parties/entity config and resolve accountants/clients.
- Key exports:
  - Initialize-EntityConfig
  - Resolve-Accountants
  - Resolve-Clients

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

- File: utils/Preview-Location.ps1
- Purpose: read-only folder navigation/preview for local and remote paths.
- Typical usage:
  - pwsh -NoProfile -File ./utils/Preview-Location.ps1 -Root "gdrive:parties/acme/rapoarte"

## Tomatoflow (recommended workflow)

Tomatoflow is an opinionated workflow package that builds on the generic utilities.

### Orchestration scripts
- File: tomatoflow/organization/Ensure-NewMonthFolder.ps1
- Purpose: creates the next missing month folder based on existing month folders.
- Typical usage:
  - pwsh -NoProfile -File ./tomatoflow/organization/Ensure-NewMonthFolder.ps1 -Path "gdrive:parties/entity/rapoarte"

- File: tomatoflow/organization/Create-MonthlyReport.ps1
- Purpose: creates next month folder and copies template files.
- Typical usage:
  - pwsh -NoProfile -File ./tomatoflow/organization/Create-MonthlyReport.ps1 -Path "gdrive:parties/entity/rapoarte"

- File: tomatoflow/organization/Label-Files.ps1
- Purpose: labels files (for example INVOICE/EXPENSE/BALANCE) for later grouping.
- Typical usage:
  - pwsh -NoProfile -File ./tomatoflow/organization/Label-Files.ps1 -Path "gdrive:parties/entity/rapoarte/_current-month"

- File: tomatoflow/organization/Archive-FilesByLabel.ps1
- Purpose: creates one archive per label and uploads/copies output.
- Typical usage:
  - pwsh -NoProfile -File ./tomatoflow/organization/Archive-FilesByLabel.ps1 -Path "gdrive:parties/entity/rapoarte/_current-month"

- File: tomatoflow/organization/Copy-ToMonthFolder.ps1
- Purpose: copies month assets between source/destination paths.
- Typical usage:
  - pwsh -NoProfile -File ./tomatoflow/organization/Copy-ToMonthFolder.ps1 -SourcePath "..." -DestinationPath "..."

- File: tomatoflow/organization/Get-LastMonth.ps1
- Purpose: returns latest month tag from a list of month names.
- Typical usage:
  - pwsh -NoProfile -File ./tomatoflow/organization/Get-LastMonth.ps1 -Values @('jan-2026','_feb-2026') -SkipInvalid

### Tomatoflow reusable modules
- File: tomatoflow/organization/modules/MonthUtils.psm1
- Purpose: month parsing and next-missing-month calculations.

- File: tomatoflow/organization/modules/LabelUtils.psm1
- Purpose: label parsing, selector generation, unique name rules.

- File: tomatoflow/organization/modules/DriveUtils.psm1
- Purpose: Drive metadata helpers and browser URL generation.

## Samples

### Sample automations menu
- File: samples/automations.json
- Purpose: demonstrates a Tomatoflow-style automation menu including placeholders for not-yet-implemented steps.

### Sample parties configuration
- File: samples/parties.json
- Purpose: demonstrates parties setup with two accountants and two clients.

## Maintenance rule

When adding or changing any base capability:
1. Update this catalog.
2. Update base/README.md if overview, scope, or package boundaries changed.
