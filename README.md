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
- `conf/parties.json`

Add your own static data, imports, and automations there. The base image is intended to remain stable for these files, and we will try to avoid changing them as much as possible to reduce merge friction for consumers.

Recommended commit message:
- `customize conf/automations.json and conf/parties.json for <your-project>`

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
