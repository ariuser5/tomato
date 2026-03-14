# Tomatoflow

Tomatoflow is a recommended workflow pattern for managing recurring entity data and periodic handoff tasks.

It is intentionally domain-agnostic:
- an entity can be any party you collaborate with;
- storage can be local filesystem or remote drives;
- folder and document lifecycle follows predictable period-based transitions.

## Purpose
- Offer a practical default workflow for recurring monthly/periodic operations.
- Keep workflow orchestration scripts separate from generic utility primitives.
- Allow adopters to use the pattern as-is or evolve their own workflow while reusing the same base capabilities.

## Package layout
- `organization/`: orchestration scripts for Tomatoflow operations.
- `organization/modules/`: reusable Tomatoflow helpers (month parsing, labeling, drive metadata).

## Relationship with utils
- `base/utils` contains generic, workflow-agnostic utilities.
- `base/tomatoflow` contains the opinionated recommended workflow implementation.
