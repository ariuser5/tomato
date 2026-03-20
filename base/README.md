# Base Layer

This folder contains the reusable base layer that extender repositories build on.

## Purpose
- Provide reusable building blocks for automation workflows.
- Keep generic utilities separated from workflow-specific orchestration.
- Offer one recommended workflow package while still supporting custom overlays.

## What is in base
- `helpers/`: config loading and automation command execution.
- `resources/`: shared assets and templates used by automations.
- `utils/`: generic workflow-agnostic utilities.
	- `utils/gdrive/`: Google Drive helper scripts.
- `tomatoflow/`: recommended workflow implementation package.

## Tomatoflow

Tomatoflow is the recommended flow provided by this base layer.

It is intentionally generic and party-oriented:
- works with entities/parties rather than a specific business type;
- works with local and remote storage;
- supports recurring period-based operations and handoff preparation.

Tomatoflow package layout:
- `tomatoflow/automations.json`: default tomatoflow automation entries.
- `tomatoflow/configure/`: setup and configuration management scripts.
- `tomatoflow/automations/scripts/`: Tomatoflow building-block scripts.
- `tomatoflow/automations/scripts/modules/`: reusable Tomatoflow-specific modules.

Tomatoflow runtime model:
- Fresh clone shows only setup automations under `tomatoflow-setup`.
- Setup automation writes per-user flow metadata file to `%LOCALAPPDATA%/tomato/tomatoflow-meta.json`.
- Configured flow folders are shown at top-level, alongside `tomatoflow-setup`.
- Flow command entries from that local file are imported at runtime (`alias`, `categoryPath`, `command`, optional `args`, optional `cwd`).
- Each configured flow gets runnable entries for monthly run, preview, ensure month folder, label files, archive by label, create draft email, and conclude month folder.
- This keeps base repository defaults clean while enabling local flow provisioning.

## Capability catalog

For a complete list of available functionality and usage examples, see:
- `docs/CATALOG.md`

This is the canonical discovery document for developers extending the base layer.
