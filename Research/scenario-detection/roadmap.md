# Roadmap: scenario detection

## Context

`feat/scenario-detection` has a working foundation: `VehicleProbe`, the `Check` nodes,
`ExamSession` with data-driven scoring, one stop junction scenario, and keyboard, gamepad and VR
play. There are 45 headless tests. The next layer is what a real exam judges:

- **Lines:** crossing or driving over road markings.
- **Parking:** both whether a spot is legal and free, and how well the manoeuvre is done.
- **More scenarios:** parking, lane change, pedestrian crossings and traffic lights, and priority
  junctions.
- **Other road users:** first as scripted path followers, then as reactive AI.

Each phase below ends green on the headless tests and is its own working-branch commit (or its
own branch). That is decided per phase, on order.

## Principles carried forward

- **One source of truth per road feature.** A marking's curve both draws the paint mesh and feeds
  detection, so what the driver sees is exactly what is judged.
- **Checks stay small and declarative.** They are scene nodes with `FaultDef` exports, and all
  scoring stays in `ScoringPolicy`.
- **The car is still read only through `VehicleProbe`.** It gains footprint and gear data that it
  derives itself.
- **Each new check gets scripted drives** in `tests/run_tests.gd`: one passing and one failing
  per rule.

Status: phases 1 to 6 are built; phase 7 is next.

## Phase 1: probe and engine upgrades (needed by everything below)

**`scenarios/core/vehicle_probe.gd`**
- **Footprint.** It exports length, width, and the wheel offsets, and computes `corners()` and
  `wheels()` in world space each tick. Lines and parking are judged on wheels and corners, not
  the centre.
- **Direction tracking.** It exposes `direction` (forward, reverse, stopped) and counts
  `direction_changes`, the "manoeuvres" count that parking limits.
- **Signals.** `stopped`, `started_moving` and `direction_changed`, so checks don't each re-derive
  them.
- **Optional live state.** Indicator (exists), plus `handbrake` and `headlights`, set by the car
  and defaulting to unknown. Checks that need unknown state skip and log rather than fault.

**`DriverView.look_direction()`.** The probe holds a reference to the car's `DriverView`, so gaze
checks read `probe.look_direction()`.

**Session improvements (`scenarios/core/exam_session.gd`)**
- **Phases inside a scenario.** An ordered list of `ScenarioStep` nodes ("park in a free bay",
  "leave the bay"), each with its own goal check. The briefing and UI show the current step
  through a new `step_changed(step)` signal.
- **Per-check enable windows.** A check is live only within named steps, so a parking check
  doesn't fault during the approach drive.
- **Fault cooldown and dedupe.** One record per check per episode, done centrally instead of in
  each check.

**`ScenarioResult`** gains `to_dict()` for the UI and for saving attempts.

## Phase 2: road markings and line detection

New `scenarios/road/` folder.

**`RoadMarking`** (`@tool`, extends `Path3D`)
- `type`: solid, dashed, double solid, stop line, give way line, zebra, bay edge, no-parking
  (yellow), kerb.
- Also `width` and `dash_length` / `gap`.
- In the editor and at runtime it builds its paint mesh from the curve (a dashed pattern along
  baked points).
- It registers with the scenario's `MarkingIndex`.

**`MarkingIndex`** (a node under `Scenario`)
- A 2D grid of baked marking segments in the XZ plane, so a lookup costs a few segments, not
  every line.
- `crossings(from, to)` returns the markings a wheel crossed this tick: a segment intersection,
  with the side it came from.
- `overlaps(point)` returns the markings a wheel sits on, using the distance to a segment against
  half the line width.

**`LineCheck`** (one per scenario, rule table as exports). Each tick, each wheel's movement is
tested against the index:

| Marking | Rule | Default fault |
|---|---|---|
| solid / double solid | any wheel crosses | serious (`line_solid_crossed`) |
| dashed | crossed without the matching indicator on | minor (`no_indicator_lane_change`) |
| dashed / solid | a wheel rides on the line longer than the grace time | minor (`line_straddled`) |
| stop / give way line | handled by `StopCheck` and `YieldCheck`; `LineCheck` ignores them | none |
| kerb | a wheel crosses it | serious (`kerb_mounted`) |

- The indicator rule is a reusable helper: the indicator must have been on for at least *t* seconds
  before the crossing. This is shared with turns.
- `StopCheck` can then take its stop line from a `RoadMarking` instead of a hand-drawn zone, and
  the same goes for the route edge in `RouteCheck`.

**Tests:**
- drift over the solid centre line: serious fault;
- dashed lane change with the indicator: none;
- without the indicator: minor;
- riding the line: minor.

## Phase 3: parking (manoeuvre quality, then legal and free)

**`ParkingBay`** (`@tool`, `Node3D`)
- A rectangle (size), the allowed headings (forward, reverse, either), and `occupied` (set by a
  parked car instance, or derived from bodies inside it).
- It draws its bay edges as `RoadMarking` bay edges.

**`ParkingCheck`** judges a manoeuvre once the car stops with the handbrake (or stays stopped for
*t* seconds):

| Rule | Fault |
|---|---|
| a footprint corner outside the bay | `parking_outside_bay` (minor up to a margin, serious beyond) |
| heading off the allowed heading by more than X° | `parking_misaligned` (minor) |
| more direction changes than allowed | `parking_too_many_manoeuvres` (minor per extra, serious past a limit) |
| over time | `parking_too_slow` (minor) |
| contact with a car or kerb | the existing `ContactCheck` and kerb faults |

**Legality and availability.** `NoParkingZone` areas come from the rules and from markings:
- yellow lines;
- within N m of a junction, crossing, or bus stop.

Each is authored as a `TriggerZone` with a reason.

**`ParkingChoiceCheck`.** When the car settles for parking (handbrake, or stopped for longer than
*t* outside a traffic context), it judges where:
- inside a no-parking zone: `parking_illegal` (serious);
- in an occupied bay: `parking_occupied`;
- partly on a free bay: handed to `ParkingCheck`;
- otherwise legal, if the step asked for "park where allowed".

**Scenarios:**
- `bay_parking`: a car park with some bays occupied at random from a seed. The task is "reverse
  into a free bay".
- `parallel_parking`: a kerbside gap between two parked cars, with a yellow line stretch before
  it.

**Tests:** for each scenario, a scripted perfect park passes, and the overhanging, misaligned,
too-many-manoeuvres, occupied-bay and yellow-line cases each produce their fault.

## Phase 4: other road users, scripted

New `scenarios/traffic/` folder.

**`ScriptedAgent`** (an `AnimatableBody3D` on the obstacle or pedestrian layer)
- It follows a `Path3D` with `PathFollow3D` at a speed profile.
- It starts on a `TriggerZone` event or a timer, can wait, and loops.
- Pedestrians are on the pedestrian layer and in the `pedestrian` group, so the existing
  `ContactCheck` already distinguishes them.

**`TrafficLight`.** It runs a state machine (red, red-amber, green, amber) on a timer or a trigger,
shows the lamps, and exposes `state` and `state_changed`.

**`AgentSpawner`.** It spawns parked cars and walkers from a seed, which also drives "free or
occupied" for parking.

Deterministic timing, from triggers and a seed, keeps the scripted drives reproducible.

## Phase 5: scenario-specific checks

| Check | Rule | Used by |
|---|---|---|
| `TrafficLightCheck` | crossing its stop line on red, or on amber when it could have stopped (distance against speed at the change) | traffic lights |
| `CrossingCheck` | a pedestrian on or stepping onto the zebra and the car enters the crossing zone: critical; stopping on the zebra: minor | pedestrian crossing |
| `YieldCheck` | entering a conflict zone while a priority agent is due there within *T* s (time to arrival from its path speed): critical; a needless stop on a clear road: minor | give way, roundabout |
| `IndicatorCheck` | a turn or exit (route branch) taken without the matching indicator for at least *t* s first; cancelling late | junctions, roundabout, lane change |
| `GazeCheck` | before a lane change, pulling out, or moving off: `look_direction()` inside the mirror or shoulder cone at some point in the *t* s window before | lane change, parking exit, moving off |
| `FollowingDistanceCheck` | time gap to the agent ahead on the same route below 2 s for longer than the grace time | overtaking |
| `RouteCheck` (extended) | branching routes: the `Path3D` routes a scenario allows, plus a wrong-turn fault | roundabout, junctions |

**Scenarios, each with a briefing and steps:**
- `lane_change_overtake`: two lanes, a slow scripted car, a solid line stretch where overtaking is
  forbidden, and a dashed stretch with mirror, shoulder and indicator checks.
- `pedestrian_crossing`: a zebra with walkers triggered as the car approaches, plus a variant with
  an empty crossing.
- `traffic_lights`: a light changing to amber as the car approaches at different distances.
- `give_way_junction` and `roundabout`: a scripted stream of priority traffic with gaps of known
  size.

## Phase 6: framework quality pass

The scenario system as an internal framework to build more scenarios on:
- Tests split into one case per framework area and per scenario, on a `TestCase` base.
- `Check` helpers (`watch`, `report_here`, `required_exports`), `Episode`, default faults, editor
  configuration warnings, and per-tick caching of the footprint and the wheel crossings.
- An authoring kit: `scenario_base.tscn`, the shared `RoadEnvironment`, kit materials and parked
  car, a definition file per scenario, and the `ScenarioCatalogue`; zones fill by role in the
  editor.
- A debug HUD and a sandbox scene that run any catalogued scenario.

## Phase 7: reactive traffic AI (after the scripted set is stable)

- **`TrafficAgent`** replaces the fixed speed profile with behaviour:
  - car following (IDM-style acceleration from the gap and closing speed);
  - stopping for red lights and give way lines;
  - yielding at crossings;
  - lane keeping on a route graph.
- **Road graph.** `RoadMarking` lanes and routes form a lane graph (lanes, connections, conflict
  zones), so agents and `YieldCheck` share one model of the junction.
- Agents react to the player (brake when cut off), and dangerous interactions become faults
  through `YieldCheck` and `FollowingDistanceCheck` on the agents' side ("caused another road user
  to brake hard").
- Determinism: a fixed seed and the fixed physics step keep tests reproducible. The AI tests
  assert outcomes such as "agent stopped" and "no collision", not exact positions.

## Authoring and tooling, alongside the phases

- **Faults.** The fault library grows in `scenarios/data/faults/`, one `.tres` per rule. The
  default policy stays generic.

## Order and size

1. Probe and session upgrades. Small; it unblocks everything.
2. Markings and lines: medium. This includes moving `StopCheck` and `RouteCheck` onto markings.
3. Parking, both kinds: medium.
4. Scripted agents and traffic lights: medium.
5. Checks and scenarios for lane change, crossing, lights, give way and roundabout: large; one
   scenario per commit.
6. Framework quality pass: medium.
7. Reactive AI: large; its own branch.

## Verification

- Every phase adds scripted drives to the headless runner, a passing and a failing case per rule:
  `godot --headless --fixed-fps 60 --path 'vr-project-[car-sim]' -s res://tests/run_tests.gd`. The import gate
  passes too.
- Each new scenario is also driven by hand (keyboard and gamepad, then a headset), and the printed
  `ScenarioResult` is compared with the expected faults.
- The `consistency` reviewer runs before each commit that touches `project.godot` or the
  agent configuration.

## Open points for the author

- Default severities and thresholds (grace times, angle and margin limits) are first guesses in
  `.tres` files, to be tuned with real drives.
- Whether a country preset policy (`ScoringPolicy` plus fault severities) is wanted once the
  scenarios exist.
- The coordination with the driving branch is unchanged: `car.gd` adopts `DriverInput`,
  `DriverView`, `VehicleProbe`, and reports its handbrake and indicators.
