# Sources: scenario detection

| Id | Source | Accessed | Facts | State |
|---|---|---|---|---|
| S1 | Godot 4.7.2 binary on this machine (`godot --help`, its project setting names) | 2026-11-16 | `--headless` with `-s <script>` runs a `SceneTree` script; `--fixed-fps` disables real-time sync. The Jolt settings under `physics/jolt_physics_3d/` hold no switch for areas detecting static bodies. | V |
| S2 | Headless test run, `tests/run_tests.gd`, on Godot 4.7.2 with Jolt | 2026-11-16 | An `Area3D` on Jolt reports a `StaticBody3D` (the parked car) through `body_entered` with no extra setting. A `CharacterBody3D` moved by setting its transform is seen by areas on the next physics step. A node added at the origin and moved in the same frame is first seen at the origin, so a spawn sets the transform before `add_child`. Without `--fixed-fps`, a headless run steps physics in real time. Jolt once logged that its job system exceeded the maximum number of jobs during the full suite, with no effect on results. `Curve3D.get_closest_offset`, `sample_baked` and `get_baked_length` in a path's local space give the lateral offset and lane direction the route drives expect. | V |
| S3 | Headless test run, as S2 | 2026-11-16 | `Object.get_meta(key, null)` still reports an error for a missing key, because a null default counts as no default; `has_meta` guards it. | V |
