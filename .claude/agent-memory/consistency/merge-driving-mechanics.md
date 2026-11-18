---
name: merge-driving-mechanics
description: Review of the dev-into-driving-mechanics merge (2026-11-18): what was checked clean and the known deferred deviations of car.gd/Car.tscn
metadata:
  type: project
---

- Merge adds `Car.tscn`, `car.gd`, `car.gd.uid` (uid matches the tscn ext_resource) and changelog entry v0.2.0-alpha (minor bump for a feature branch, releasing rule). project.godot keeps `config/features ("4.7","Mobile")`, Vulkan on Windows, Jolt, separate physics thread. Changelog entry has no dashes and follows the format. Clean.
- Known deferred deviations in `car.gd`/`Car.tscn` (author keeps as written, to fix in the PR): reads raw keys instead of `DriverInput` actions (against README "Bindings are input actions" and the v0.1.0 changelog "Rebind every control"); own mouse look and `XROrigin3D` instead of `DriverView`; default collision layer rather than the vehicle layer (2); debug prints. `Research/README.md` open flags already record the first two and the d3d12 note.
- Branch name `driving-mechanics` has no `feat/` prefix (versioning rule); the branch predates the rule.
- `Research/README.md` d3d12 flag still reads as pending after the merge; fine to leave or reword once the merge is committed.
