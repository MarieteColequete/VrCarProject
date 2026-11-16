---
name: settled-decisions
description: Settled VrCarProject boundaries looked up in the scenario-detection review (2026-11-16), and checks that came back clean
metadata:
  type: project
---

- Engine pin: Godot 4.7, Forward Plus, Jolt (`CLAUDE.md` Architecture; `.claude/rules/project/implementation.md`). `project.godot` `config/features` must stay `("4.7", "Forward Plus")`. The `driving-mechanics` remote branch sets Mobile; known and flagged in `Research/README.md`.
- Physics layers named in `project.godot` [layer_names]: 1 world, 2 vehicle, 3 obstacles, 4 pedestrians, 5 detection; they match the bit constants in `scenarios/core/vehicle_probe.gd`. Check both stay in step.
- `CLAUDE.md` states "no automated tests yet" in the testing-method line; any change adding tests (e.g. `tests/run_tests.gd`) makes that line stale and needs a `CLAUDE.md` edit plus a Commands entry.
- Decision record: none; decisions go in commit bodies and `CLAUDE.md`. A `Research/*/brief.md` "Author decisions" list is allowed by the research-cache rule but is not the record.
- Source states in `sources.md`: V = primary source read, V2 = two independent secondary sources, U = unverified. Class reference pages count as primary (V), not V2.
- Version and changelog change once per merge request as the branch's last step (releasing rule); a `feat/` branch bumps the minor.
- Tooling note: the consistency agent has no Bash, so `git diff` is unavailable; use Glob/Grep/Read on the untracked and edited files.
- Dash check (en and em dash characters) over README, Research, scenarios, tests came back clean on 2026-11-16.
