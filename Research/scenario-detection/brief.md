# Brief: scenario detection

Resume point for the scenario and detection foundation (`vr-project-[car-sim]/scenarios/`).

## Findings that drive the design

- Detection is decoupled from the car by `VehicleProbe`, which derives speed and heading from its
  own transform each physics tick (S2). Any car body works; the probe also carries the contact
  hull, an `Area3D` masked to obstacles and pedestrians.
- Zones are `Area3D` nodes on the detection layer, masked to the vehicle layer (S2). Static
  obstacles are detected on Jolt without a setting (S1, S2).
- Lanes are `Path3D` centrelines; the lateral offset and travel direction come from the closest
  baked offset and a finite difference along the curve (S2). The tangent is computed by
  difference rather than from `sample_baked_with_rotation`, to avoid depending on its axis
  convention.
- Scripted drives move the car one step per physics tick, so tests are deterministic and take
  well under a second (S1, S2).

## Open questions

| Question | Options | Depends on | Status |
|---|---|---|---|
| Should the scenario tests join the stop gate? | Chain them after the import in `.claude/project.json`; keep them a manual command | how the gate runs a compound command | OPEN |
| Road edge for `RouteCheck` | One symmetric offset from the lane centre (now); separate left and right edges per lane | multi-lane scenarios | OPEN |
| Gaze checks (mirrors, shoulder) | `XRCamera3D` forward inside a cone within a time window before a manoeuvre | the driving branch's indicators | OPEN |
| A country preset | A second `ScoringPolicy` file with that exam's tiers and limits | choice of exam | OPEN |

## Author decisions

- Scoring is generic: tiers and limits are data in a `ScoringPolicy`, no country built in.
- The first milestone is one complete scenario, the stop junction.
- Detection reads the car through an adapter; the driving branch's `car.gd` is not edited.
- The work targets Forward Plus on `dev`; the driving branch's switch to the Mobile renderer is
  flagged for its merge.
