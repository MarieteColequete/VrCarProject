# VrCarProject

A car driving simulator for virtual reality, built with Godot 4.7 and OpenXR, that turns the
situations of the practical driving exam into scenarios driven in VR.

## Controls

The simulator is built for a headset and a driving wheel, and it also plays flat on a monitor with a
keyboard and mouse or a gamepad. Bindings are input actions in `project.godot`, so a device is
added or remapped there without code changes; car scripts read them through `DriverInput`.

| Action | Keyboard and mouse | Gamepad |
|---|---|---|
| Throttle | W, Up | Right trigger |
| Brake, then reverse once stopped | S, Down | Left trigger |
| Steer | A and D, Left and Right | Left stick |
| Handbrake | Space | A (Cross) |
| Indicators | Q and E | Left and right shoulder |
| Look around | Mouse | Right stick |
| Recentre the view | C | Right stick click |
| Driver or chase view | V | Select |
| Free the mouse, recapture it | Escape, click | |

`DriverView` is the driver's head in a car scene. With an OpenXR headset running, the headset turns
the view; otherwise the mouse and the right stick turn a flat camera within a seated driver's
range, and its `look_direction()` is the same in both modes.

## Scenarios

A scenario is a scene under `vr-project-[car-sim]/scenarios/scenes/` whose root carries the
`Scenario` script. It holds the world, a `Marker3D` spawn point, and the checks that judge the
drive. Its `ScenarioDefinition` gives the title, the briefing, the time limit, the scoring policy,
and the car scene to spawn.

Checks are nodes placed in the scene, each watching one rule:

| Check | Rule |
|---|---|
| `StopCheck` | A complete stop inside the approach zone before the line zone is entered |
| `SpeedLimitCheck` | The speed limit over a zone, with a grace time and a serious margin |
| `RouteCheck` | Staying in the lane of a `Path3D` centreline, on the road, and not against traffic |
| `LineCheck` | Crossing a solid line, crossing a dashed line without indicating that way, riding on a line, mounting a kerb |
| `ContactCheck` | No contact with obstacles or pedestrians |
| `GoalCheck` | Reaching the goal zone completes the attempt |

Zones are `TriggerZone` areas with a collision shape drawn in the editor. Road markings are
`RoadMarking` paths (solid, dashed, double solid, stop and give way lines, zebra, bay edge,
no-parking line, kerb): the curve draws the paint and is also what `LineCheck` judges, on the
car's wheels rather than its centre. A scenario can run as ordered `ScenarioStep`s, each ended by
its own `GoalCheck`, and a check can be limited to some steps. Each fault a check reports
is a `FaultDef` resource in `scenarios/data/faults/`, naming a severity tier. A `ScoringPolicy`
resource defines the tiers, which of them eliminate at once, and how many faults of each an
attempt may collect and still pass; `default_policy.tres` is a generic policy, and a particular
exam is another policy file.

The car only needs a `VehicleProbe` child, which derives speed and heading from the car's motion
and reports contact. `ExamRunner` (`scenarios/scenes/exam_runner.tscn`) spawns a scenario and its
car and runs an `ExamSession`. The session's signals (`briefing_started`, `started`,
`fault_committed`, `finished`) and methods (`begin`, `abort`, `restart`) are the interface for the
UI; `finished` carries a `ScenarioResult` with the outcome and every fault.

The scenario tests run headless:

```
godot --headless --path 'vr-project-[car-sim]' -s res://tests/run_tests.gd
```
