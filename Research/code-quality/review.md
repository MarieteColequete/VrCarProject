# Code quality review: the functional ECS runtime

Prepared 2026-11-18, after the move to the functional ECS, for a later quality pass, and acted on
the same day: every item is done or settled as marked. Scope: modularisation and optimisation of
`vr-project-[car-sim]/scenarios/` (paths below are relative to it). Costs are per physics tick on
the development machine, debug build, busy junction plus 200 stress road users, from
`WorldRunner.timings` (`../scenario-detection/performance.md`, Functional ECS); estimates are
marked as such.

## Why it mattered

In the first version, under the 200 road user stress load the main thread spent about 5.7 ms per
tick, and through an emulated headset 27% of frames ran late in one 20 s run, against none in the
two 10 s runs just before the move (same load). The cost was GDScript touching one object per road
user per tick. Item 1 fixed it: the tick is about 2.6 ms and the stress runs are clean again
(`../scenario-detection/performance.md`). The quality pass's first part, items 5, 7, 9, 10 (in
part), and 11, took the stress tick from 2.62 ms to 2.39 ms. The second part, the rest, took it
from 2.76 ms to 1.96 ms on one harness (mean of runs; the harness reads higher than the earlier
figures, so the two parts are compared each against its own baseline): begin 0.74 to 0.53 ms,
views 0.76 to 0.31 ms, the exam 0.28 to 0.21 ms. Through Monado at 2.2 times the eye size, two
stress runs had no late frame (p99 14.1 and 13.8 ms).

## Optimisation, most valuable first

1. **Road-user state as packed columns.** Done: the road users are an `AgentTable` of packed
   columns; a tick copies them, thinks and commits over rows, and hands them back whole through
   `Delta.write_column`. Commit and begin went from 2.7 ms to 0.95 ms, the whole stress tick from
   5.7 ms to 2.6 ms. The configuration columns are now shared, not copied, by the tick's table:
   nothing changes them after spawn, so they stay in the one agent component rather than a second
   one whose rows would have to be kept aligned. The view's part is item 8.
2. **Lane rules scanned every road user per priority lane.** Done: road users are bucketed by
   lane once per tick (`LaneRules.by_lane`), each lane's meeting point with each priority lane is
   an offset baked in the `RouteTable`, and a road user's own progress is used instead of a
   projection. Rules are evaluated only for lanes a road user stands on.
3. **Routes were built every tick.** Done: `RouteTable` holds the lanes as packed columns by slot,
   built once and again only when lanes are added; `LaneRules.evaluate` fills only the per-tick
   flags (light red, light amber, way clear, crossing busy). `TrafficSnapshot.Route` is gone.
4. **Workers read shared objects.** Done: thinking reads the route columns and flags aliased into
   the `AgentTable`'s own fields (`use_routes`), and the sensor writes its hit into a packed array.
   Lanes are still sampled through their `Curve3D` on worker threads; thinking in parallel waits
   as long as before (1.1 ms, against 3.6 ms inline), so a baked polyline was not taken up.
5. **`World.apply` builds an Array per write.** Done: it reads the delta's parallel arrays
   directly and keeps the store across consecutive writes.
6. **`ExamLogic` rebuilt dictionaries and copied growing state.** Done: rules are read as columns
   in row order, which is scene order (no sort); the session's faults and dedupe table are copied
   only when a fault is reported, and dedupe entries past the window are dropped then; only rule
   states and session columns that changed are written. The frame's road users are the tick's
   shared view (`AgentTable.read`, cached on the store's change count).
7. **`CarState.read` ran four times per tick.** Done: it is read once while the vehicle's columns
   are unchanged, through a cache keyed on the store's change count (`World.memo`).
8. **`TrafficView.draw` copied its buffer and static data every tick.** Done: the two buffers
   swap; colour is written once per slot; transforms are built from the position and facing
   columns in one loop. Views went from 0.76 ms to 0.31 ms.
9. **`sorted_ids()` copied and sorted on every call.** Done: the store keeps them, rebuilt after
   an add or remove; lights and sources iterate rows instead.
10. **Small systems built a dictionary per row.** Done in part, the rest settled: zones alias
    their columns and write only the flags that changed; lights and sources read rows from the
    columns. The light, source, and vehicle steps keep taking their row as a value: they are pure
    and tested on their own, and run over a dozen rows or one.
11. **Scheduling overhead.** Done: the runner keeps its sorted stage list.

## Modularisation

12. **The lane's crossing warning always fired**: it checked a removed method. Done: it checks
    for a crossing zone.
13. **Dead code from the old runtime.** Done: removed `TriggerZone.contains_point`, the
    `ParkingBay` geometry queries, the layer groups, `Episode`'s object form,
    `TrafficLight.is_red_state`, `LaneData.tangent_at` and `has_rules`, `World.has_component`, and
    the unread lane component (the lanes resource is the source).
14. **A lane was built in two places.** Done: `LaneData.of` is the one constructor, used by
    `Bake.lane_of` and `Simulation.add_path`.
15. **Helpers in the wrong module.** Done: `ground_direction` is in `Geo`; a crossing's stop reads
    the zone's `box_data` instead of `TrafficLane._half_depth`, which is gone; `&"lanes"` is
    `Schema.LANES`.
16. **Doc comments that did not match the code.** Done: the five found are corrected.
17. **`AgentTable.think` was long.** Done: it is four parts, what is ahead (`_ahead`), the speed
    (`_decide_speed`), hard braking (`_decide_braking`), and the clear neighbour lanes
    (`_clear_sides`).
18. **`TrafficView` never released a removed road user's slot or body.** Done: a road user that
    left the world frees its body, and the last slot moves into its place.
19. **Rules run on dictionaries.** Done in part: each rule's step and finish are bound as
    `Callable`s at bake, and only changed states are written. Rules still return a fresh state
    and `RuleResult` per tick; at about 20 rules that is kept for plainness.

## Author decisions

