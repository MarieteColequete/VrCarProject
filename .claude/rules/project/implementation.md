---
paths:
  - "**/*.gd"
  - "**/*.tscn"
  - "**/*.tres"
  - "**/project.godot"
---

# VrCarProject implementation specifics

The project is Godot 4.7 with GDScript; these are its own conventions.

- **Naming is exact.** The Godot project folder is `vr-project-[car-sim]`, and the scenes and
  scripts are referenced by their `res://` paths and `.uid` files: a rename is made in the editor,
  which updates the references, never by moving files on disk alone.
- **Engine pinned.** The project stays on Godot 4.7 with the Forward Plus renderer and Jolt
  physics (`project.godot`); changing any of them is a decision of its own.
- **Gates.** The headless import check in `CLAUDE.md` passes before a merge request. No hosted CI
  runs it yet.

## Enforced by

The `gate` in `.claude/project.json` (the headless import check, run when a turn ends), and the
`allow` entry for `godot --headless` in `.claude/settings.json`.
