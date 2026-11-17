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
| Begin the attempt after the briefing | Enter | Start |
| Restart the attempt | R | Y (Triangle) |
| Next scenario, in the sandbox | N | D-pad right |
| Show or hide the debug HUD | F1 | Left stick click |

`DriverView` is the driver's head in a car scene. With an OpenXR headset running, the headset turns
the view; otherwise the mouse and the right stick turn a flat camera within a seated driver's
range, and its `look_direction()` is the same in both modes.

## Scenarios

A scenario is a scene under `vr-project-[car-sim]/scenarios/scenes/<name>/` that inherits
`scenarios/kit/scenario_base.tscn`. The base gives the `Scenario` root, the shared
`RoadEnvironment` (daylight, sky, and a grass ground sized per scenario), a `SpawnPoint`, a
`Markings` node, and a `Checks` node already holding `ContactCheck`, `LineCheck`, and
`TrafficConflictCheck`. The scenario
adds its roads, markings, other road users, zones, and checks. Scenarios are laid out with the car
driving towards -Z in the right-hand lane, centred on x = 1.75.

Its `ScenarioDefinition`, `definition.tres` beside the scene, gives the id, the title, the menu
category and difficulty, the briefing, the time limit, the scoring policy, and the car scene to
spawn. `scenarios/catalogue.tres`, a `ScenarioCatalogue`, lists every definition in menu order;
menus read it and start a scenario with `ExamRunner.load_definition`.

Checks are nodes placed in the scene, each watching one rule:

| Check | Rule |
|---|---|
| `StopCheck` | A complete stop inside the approach zone before the line zone is entered |
| `SpeedLimitCheck` | The speed limit over a zone, with a grace time and a serious margin |
| `RouteCheck` | Staying in the lane of a `Path3D` centreline, on the road, and not against traffic |
| `LineCheck` | Crossing a solid line, crossing a dashed line without indicating that way, riding on a line, mounting a kerb |
| `ParkingCheck` | Once settled in a `ParkingBay`: overhanging it, facing the wrong way, too many direction changes, taking too long |
| `TrafficLightCheck` | Crossing the stop line on red, or on amber when the car could have stopped as it changed |
| `CrossingCheck` | Driving onto a pedestrian crossing while someone is on it or about to cross, stopping on it |
| `GazeCheck` | Changing lanes (or moving off) without first looking in the mirror and over the shoulder on that side |
| `FollowingDistanceCheck` | Staying under a two second time gap behind a road user in the same lane |
| `YieldCheck` | Entering a conflict zone while a road user with priority is in it or due within a safe gap, and waiting too long when the way is clear |
| `JunctionCheck` | Leaving a junction or roundabout by a `JunctionExit` the route does not take, or without indicating that way, read on approach or, at a roundabout, on leaving |
| `ParkingChoiceCheck` | Once settled: parking in a `NoParkingZone` or by a no-parking line, in a reserved bay, or in an occupied one |
| `ContactCheck` | No contact with obstacles or pedestrians |
| `TrafficConflictCheck` | Getting in another road user's way so that it has to brake hard |
| `GoalCheck` | Reaching the goal zone completes the attempt |

Zones are `TriggerZone` areas with a collision shape drawn in the editor. Road markings are
`RoadMarking` paths (solid, dashed, double solid, stop and give way lines, zebra, bay edge,
no-parking line, kerb): the curve draws the paint and is also what `LineCheck` judges, on the
car's wheels rather than its centre. A `ParkingBay` is a parking space, nose-in, reversed, or
either, that may be reserved or occupied; a kerbside space for parallel parking is a bay along the
road. The car counts as parked once it stops with the handbrake on, or stays stopped for a few
seconds. A scenario can run as ordered `ScenarioStep`s, each ended by
its own `GoalCheck`, and a check can be limited to some steps. Each fault a check reports
is a `FaultDef` resource in `scenarios/data/faults/`, naming a severity tier. A `ScoringPolicy`
resource defines the tiers, which of them eliminate at once, and how many faults of each an
attempt may collect and still pass; `default_policy.tres` is a generic policy, and a particular
exam is another policy file.

Other road users play a script by the book until they are forced to react. A `ScriptedAgent` is a
car or a pedestrian following a `Path3D` at a set speed, starting after a delay or when the car
enters a trigger zone, with an optional pause and loop; it reports how long it needs to reach any
point of its path. While its way is clear it moves exactly as scripted, so an attempt plays out the
same way each time. A `TrafficSensor` sweeps the path ahead every tick, and when something is in
the way (the player's car, another road user, a pedestrian, an obstacle) the agent slows or stops
by the Intelligent Driver Model, then returns to its script. It reports each change through its
`reacted` signal, and braking harder than its `hard_brake` through `forced_to_brake`; a pedestrian
waits for a car standing on its way.

Roads are described for road users by `TrafficLane` paths, each along a lane's centre in the
direction of traffic: its speed limit, the lanes it continues onto, its light and stop line, the
lanes it gives way to, its pedestrian crossings, and the lanes beside it. An agent whose path is a
lane keeps to the limit, stops at the line on red (and on amber where it can still stop), waits at
the line until the priority lanes are clear of road users and of the player's car for the lane's
safe gap, waits before a crossing in use, and continues onto the next lane named in its `route`,
or picked from its `route_seed`. In the editor a lane shows its direction and its stop line. A `TrafficLight` cycles on timers, or holds green until the car approaches and
then changes, so a scenario can place the change at a chosen distance. An `AgentSpawner` fills
parking bays with parked cars chosen from a seed: the same seed gives the same car park.

The car only needs a `VehicleProbe` child, which derives speed and heading from the car's motion
and reports contact. `ExamRunner` (`scenarios/scenes/exam_runner.tscn`) spawns a scenario and its
car and runs an `ExamSession`. The session's signals (`briefing_started`, `started`,
`fault_committed`, `finished`) and methods (`begin`, `abort`, `restart`) are the interface for the
UI; `finished` carries a `ScenarioResult` with the outcome and every fault. Its `to_dict()` gives
the same as plain data: the scenario, the outcome, each fault with its description, and each tier's
count against the policy's limit.

`scenarios/debug/scenario_sandbox.tscn` runs any catalogued scenario with the `DebugHud`, a flat
overlay showing the briefing, the current step, the time against the limit, faults as they are
committed, how other road users react, and the result. It runs from the editor. The HUD only
listens to the runner, the session, and the road users' signals, so it is also a working example
of a UI on them; it hides itself in a headset.

### Building a scenario

1. Create `scenarios/scenes/<name>/<name>.tscn` as a new inherited scene of
   `scenarios/kit/scenario_base.tscn`, and set the environment's ground size to cover the roads.
2. Add the roads (meshes with `scenarios/kit/asphalt.tres`), the `RoadMarking` paths under
   `Markings`, parked cars (`scenarios/kit/parked_car.tscn`), and any scripted road users.
3. Add the checks under `Checks`, each with its zones as children. Faults default to the right
   `FaultDef`, so only a different fault needs setting. The editor flags a check missing a zone,
   and fills each zone with a colour by role: green for a goal, blue for a junction exit, yellow
   for no parking, red where the car must give way or stop.
4. Create `definition.tres` beside the scene, set the scene root's `definition` to it, and add it
   to `scenarios/catalogue.tres`.
5. Add `tests/cases/scenario_<name>_test.gd` with a clean drive and one failing drive per rule.

The scenario tests run headless, one case file per framework area and per scenario under
`tests/cases/`:

```
godot --headless --fixed-fps 60 --path 'vr-project-[car-sim]' -s res://tests/run_tests.gd
```

`TESTS_FILTER=<name>` runs only the cases whose file name contains it, and `TESTS_VERBOSE=1` prints
each passing test.
