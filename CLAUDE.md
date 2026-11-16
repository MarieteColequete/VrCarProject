# CLAUDE.md

## What VrCarProject is

VrCarProject is a car driving simulator for virtual reality, built with Godot 4.7 (Forward Plus
renderer, Jolt physics) and OpenXR. The Godot project is `vr-project-[car-sim]/`; the repository
root holds the project's documentation and the agent configuration. The repository is hosted on
GitHub (`MarieteColequete/VrCarProject`).

## Project status

Alpha. The version is the newest entry of `CHANGELOG.md`.

Status catalogues (read before assuming a feature's state):

- `CHANGELOG.md`: what each version changed.

## Source of truth

Read the relevant document before working; do not duplicate their content here.

- `README.md`: what the project is.
- `vr-project-[car-sim]/project.godot`: the engine version, renderer, physics engine, and project
  settings.

## Architecture

- `vr-project-[car-sim]/` is the Godot project: scenes (`.tscn`), GDScript (`.gd`), and resources
  such as the OpenXR action map (`openxr_action_map.tres`). The engine writes `.godot/`, which is
  not tracked.
- The project stays on Godot 4.7 with the Forward Plus renderer; an engine or renderer change is a
  decision of its own.

## Hosting

The repository is on GitHub. The preset's GitLab parts do not apply yet: the hosting check
(`/hosting`), the landing (`preset land`, the `land` skill), and the pipeline (`.gitlab-ci.yml`,
`.gitlab/ci/`) are installed but inactive, and the signature check is not switched on.
`.allowed_signers` lists one maintainer's key so far.

## Commands

Build and test in the dev container when podman is reachable, else on the host. The Godot 4.7
binary is on `PATH` as `godot`.

```
godot --headless --path 'vr-project-[car-sim]' --import   import and scan the project, then quit (the stop gate)
godot --headless --path 'vr-project-[car-sim]' -s res://tests/run_tests.gd
                                                          run the scenario tests (exit 1 on failure)
godot --path 'vr-project-[car-sim]' --editor              open the project in the editor
sh .claude/bin/preset status                              the branch, its commits, the version, and the hook
```

## Agent configuration

Rules in `.claude/rules/`, skills in `.claude/skills/`, the preset's tool in `.claude/bin/`
(`preset help`), project data in `.claude/project.json`. Working material goes to `Research/`.

The project facts the preset rules refer to:

- **Authoritative documents**: `README.md` and `vr-project-[car-sim]/project.godot`.
- **Decision record**: none yet; decisions are recorded in the commit bodies and in `CLAUDE.md`.
- **MSC document**: none.
- **Review subagent**: `consistency` (`.claude/agents/`).
- **Testing method**: the headless import check, and the headless scenario tests in
  `vr-project-[car-sim]/tests/run_tests.gd` (scoring, and scripted drives through each scenario);
  both commands are above. No separate testing document exists yet.
- **Main paper**: none yet; one is planned, and its path goes here once it exists.

## Compact instructions

Keep the current branch, the task with its acceptance checks, the decisions taken, and any failing
check. Drop orders to commit, push, or release: each needs a fresh order.
