# tomato
This repository contains a reusable base for PowerShell automation workflows.

## Repository layout
- `conf/`: root configuration for automation menu imports.
- `base/`: shared "base image" content that other projects can consume and customize.
	- `base/helpers/`: config-loading and automation-invocation modules.
	- `base/utils/`: reusable generic utilities used by automations and workflows.
			- `base/utils/gdrive/`: Google Drive helper scripts.
		- `base/utils/common/`: cross-cutting helpers (external command wrappers, result/output helpers).
	- `base/tomatoflow/`: recommended workflow implementation package.
		- `base/tomatoflow/automations/scripts/`: Tomatoflow building-block scripts.
		- `base/tomatoflow/automations/scripts/modules/`: reusable Tomatoflow-specific modules.
- `Start-Main.ps1`: interactive root entrypoint that launches the base runtime.

## Design intent
- Keep the root folder available for extender projects (custom overlays).
- Keep generic, reusable automation logic under `base/`.
- Add project-specific automations outside `base/` so base workflows remain clean and shareable.

## Use this as a base image

If you want your own customized workflows, create your own repository and consume this repo as a base source.

### Recommended repository model
- `your-workflows` (your repo): where you commit your custom automations, static data, and project-specific files.
- `tomato` (this repo): base image source, used as fetch-only remote.

### One-time setup
1. Create and clone your own repository.
2. Add this repository as an additional remote (named `base` in this example).
3. Fetch and merge the base branch into your repo.

Example:

```powershell
git clone <your-repo-url>
cd <your-repo-folder>

git remote add base <tomato-repo-url>
git fetch base
git merge base/main
```

### Make base remote fetch-only (safety)
Disable pushing to the base remote so your custom changes never go there by accident.

```powershell
git remote set-url --push base DISABLED
git remote -v
```

Expected behavior:
- `origin`: your repo (fetch + push)
- `base`: this repo (fetch only)

### Daily workflow
1. Commit and push your customization work to `origin`.
2. Periodically pull base updates from `base/main` and merge into your main branch.
3. Push merged result back to `origin`.

Example:

```powershell
git fetch base
git checkout main
git merge base/main
git push origin main
```

### Customize configuration after first base merge
After your first merge from the base image, create a dedicated commit in your own repo where you update:
- `conf/automations.json`

Add your own static data, imports, and automations there. The base image is intended to remain stable for these files, and we will try to avoid changing them as much as possible to reduce merge friction for consumers.

Recommended commit message:
- `customize conf/automations.json for <your-project>`

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
	- Shared environment setup for launched automations (`TOMATO_ROOT`, `BASE_DIR`, `UTILS_ROOT`)

### Configuration model
- Base automation config entrypoint: `conf/automations.json`
- Supports `import.path` so projects can compose local/custom overlays.
- Relative import paths resolve from the JSON file that declares the import.
- Missing or invalid import files are ignored to keep startup resilient.
- By default it also imports `%LOCALAPPDATA%/tomato/tomatoflow-meta.json` for user-local tomatoflow runtime entries.

### Editor selection for todo-style flows
- Editor resolution order:
	1. `TOMATO_EDITOR`
	2. `VISUAL`
	3. `EDITOR`
	4. fallback: `notepad.exe`

### Run
- From repository root:
	- `pwsh -NoProfile -File ./Start-Main.ps1`

## Utility framework conventions

### Split workflow scripts from reusable modules
- Keep workflow-agnostic utilities under `base/utils`.
- Keep the recommended workflow implementation under `base/tomatoflow`.
- Keep Tomatoflow building-block scripts under `base/tomatoflow/automations/scripts/*.ps1`.
- Move reusable logic into modules under:
	- `base/utils/common/*.psm1` (generic)
	- `base/tomatoflow/automations/scripts/modules/*.psm1` (workflow-specific)
- Prefer importing modules instead of duplicating helper functions across scripts.

### Output contract for script composition
- Use `Write-Host` for human-readable logs and progress.
- Use `Write-Output` only for final machine-consumable results.
- Final script output should be a single structured object (for example via `New-ToolResult`).

### External command consistency
- Use shared wrappers from `base/utils/common/CommandUtils.psm1`:
	- `Assert-RcloneAvailable`
	- `Invoke-Rclone`
	- `Test-ExecutableAvailable`
- Avoid repeating raw command/exit-code handling inline in each script.

### Promotion rule for custom overlays
- Keep project-specific logic in your custom overlay repo by default.
- Promote code to `base/utils` only when it is generic and reusable across projects.
- If logic is specific to the recommended workflow pattern, place it in `base/tomatoflow`.
