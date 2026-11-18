# CLAUDE.md

## What VrCarProject is

VrCarProject is a car driving simulator for virtual reality, built with Godot 4.7 (Mobile
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
- The game is VR only, for PC VR and standalone headsets. The project stays on Godot 4.7 with the
  Mobile renderer, the one Godot recommends for XR and the only one standalone headsets run; an
  engine or renderer change is a decision of its own.
- The runtime is a functional ECS: state lives in a `World` of component stores
  (`scenarios/ecs/`), systems are pure static functions returning deltas
  (`scenarios/sim/`, `scenarios/rules/`), and only the shell touches nodes, input, and servers
  (`WorldRunner`, `Bake`, the views in `scenarios/shell/`). Scenario scenes are the authoring side,
  baked into the world when they load; detection and scoring are geometry, never physics queries.
- The simulation is spread across cores: the physics step runs on a thread of its own
  (`physics/3d/run_on_separate_thread` in `project.godot`), and road users think on worker
  threads, applied in a fixed order. Traffic and scoring are reproducible by construction; only the
  player's own car physics is best effort. Code run on worker threads reads its own fields and
  plain arrays and creates no script objects: the engine validates other objects and counts script
  references under shared locks. Rendering stays on the main
  thread (`rendering/driver/threads/thread_model=1`, Safe), by decision: Godot's separate render
  thread is experimental and aborted the process at exit under OpenXR.
  `Research/scenario-detection/performance.md` has the method and the numbers;
  `Research/godot-threading-vr/` sets them against the state of the art.
- The world ticks at a fixed 60 Hz and rendering follows the headset's own rate; physics
  interpolation (`physics/common/physics_interpolation`) draws the bodies in between. In the game,
  a body that jumps (a spawn, a restart, a looping road user's wrap) calls
  `reset_physics_interpolation()`.
- OpenXR is enabled with a flat fallback for development and no startup alert (`[xr]` in
  `project.godot`). `DriverView` picks the headset or the flat camera, and quits when the runtime
  asks the application to close.

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
godot --headless --xr-mode off --fixed-fps 60 --path 'vr-project-[car-sim]' -s res://tests/run_tests.gd
                                                          run the scenario tests (exit 1 on failure;
                                                          --fixed-fps 60 runs them faster than real time;
                                                          TESTS_FILTER=<name> runs matching cases only,
                                                          TESTS_FILTER=bench times the detection and
                                                          traffic work; --xr-mode off keeps an active
                                                          OpenXR runtime out of headless runs)
godot --path 'vr-project-[car-sim]' -s res://tests/xr_check.gd
                                                          run the game through the active OpenXR runtime
                                                          and report late frames (XR CHECK PASS or
                                                          FAIL; exit 1 on failure)
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
- **Testing method**: the headless import check, and the headless scenario tests: the runner
  `vr-project-[car-sim]/tests/run_tests.gd` runs each case in `tests/cases/` (the framework, and
  scripted drives through each scenario, and hand-stepped worlds with no scene) on the `TestCase`
  base in `tests/lib/`; both commands are above. `tests/xr_check.gd` runs the game through an OpenXR runtime and is not a gate: it needs a
  runtime and a GPU. No separate testing document exists yet.
- **Main paper**: none yet; one is planned, and its path goes here once it exists.

## Compact instructions

Keep the current branch, the task with its acceptance checks, the decisions taken, and any failing
check. Drop orders to commit, push, or release: each needs a fresh order.
