# tomato
This repository contains a reusable base for PowerShell automation workflows.

## Repository layout
- `conf/`: root configuration for parties and automation menu imports.
- `base/`: shared "base image" content that other projects can consume and customize.
	- `base/helpers/`: config-loading and automation-invocation modules.
	- `base/gdrive/`: Google Drive helper scripts.
	- `base/gmail/`: Gmail helper scripts.
	- `base/utils/`: reusable utilities used by automations and workflows.
- `Start-Main.ps1`: interactive root entrypoint that launches the base runtime.

## Design intent
- Keep the root folder available for extender projects (custom overlays).
- Keep generic, reusable automation logic under `base/`.
- Add project-specific automations outside `base/` so base workflows remain clean and shareable.

## Entrypoint
- Start from `Start-Main.ps1`.

## Base runtime guide

### Prerequisite
- rclone (for Google Drive access)
	- Install (Windows): `winget install Rclone.Rclone`
	- Configure once: `rclone config` and create a `drive` remote (for example `gdrive`)

### Interactive app behavior
- The main app is interactive and focuses on discovery/launch, not business logic.
- `Start-Main.ps1` provides:
	- Automation menu execution from JSON metadata
	- Read-only client/accountant location browsing through preview screens
	- Shared environment setup for launched automations (`TOMATO_ROOT`, `BASE_DIR`, `UTILS_ROOT`)

### Configuration model
- Base automation config entrypoint: `conf/automations.json`
- Base parties config entrypoint: `conf/parties.json`
- Both support `import.path` so projects can compose local/custom overlays.
- Relative import paths resolve from the JSON file that declares the import.
- Missing or invalid import files are ignored to keep startup resilient.

### Editor selection for todo-style flows
- Editor resolution order:
	1. `TOMATO_EDITOR`
	2. `VISUAL`
	3. `EDITOR`
	4. fallback: `notepad.exe`

### Run
- From repository root:
	- `pwsh -NoProfile -File ./Start-Main.ps1`
