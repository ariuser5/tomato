# tomato
This repository contains a reusable base for PowerShell automation workflows.

## Repository layout
- `base/`: shared "base image" content that other projects can consume and customize.
	- `base/entity/`: entrypoint app, automation registration, and entity-specific resources.
	- `base/gdrive/`: Google Drive helper scripts.
	- `base/gmail/`: Gmail helper scripts.
	- `base/utils/`: reusable utilities used by automations and workflows.

## Design intent
- Keep the root folder available for extender projects (custom overlays).
- Keep generic, reusable automation logic under `base/`.
- Add project-specific automations outside `base/` so base workflows remain clean and shareable.

## Entrypoint
- Start from `base/entity/App-Main.ps1`.
