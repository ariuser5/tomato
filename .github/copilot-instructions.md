# Copilot Instructions for tomato

## Project Purpose
- This repository orchestrates accounting and monthly-report workflows with PowerShell.
- The entrypoint is `Start-Main.ps1`, which discovers and runs automations from JSON metadata.
- Shared/base workflow building blocks live under `base/` (`base/helpers`, `base/gdrive`, `base/gmail`, `base/utils`).
- Configuration entrypoints live at the repository root under `conf/`.
- The repository root is intentionally kept open for extender/custom overlays that should not be part of the base image.

## Automation Conventions
- Keep automation commands compatible with `base/helpers/AutomationConfig.psm1` expectations (`alias` + `command`).
- Assume `Start-Main.ps1` sets these env vars before running automations:
  - `TOMATO_ROOT`
  - `BASE_DIR`
  - `UTILS_ROOT`

## PowerShell Style
- Use `[CmdletBinding()]` and a `param()` block for new scripts.
- Keep `$ErrorActionPreference = 'Stop'` in scripts that orchestrate workflows.
- Fail fast with clear messages when required files, paths, or config values are missing.
- Preserve existing script behavior and avoid changing interactive UX unless explicitly requested.

## JSON and Paths
- Treat JSON config as user-editable; validate required fields before execution.
- Support both relative and absolute paths where possible.
- Do not hardcode machine-specific absolute paths in committed scripts.

## Changes and Safety
- Make minimal, targeted edits that preserve current public aliases and commands.
- Avoid introducing new dependencies if PowerShell built-ins can solve the task.
- Update README or samples when new automation parameters or flows are introduced.
