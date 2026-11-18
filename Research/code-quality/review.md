# Code quality review: the functional ECS runtime

Prepared 2026-11-18, after the move to the functional ECS, for a later quality pass. Nothing here
has been acted on except where marked done. Scope: modularisation and optimisation of
`vr-project-[car-sim]/scenarios/` (paths below are relative to it). Costs are per physics tick on
the development machine, debug build, busy junction plus 200 stress road users, from
`WorldRunner.timings` (`../scenario-detection/performance.md`, Functional ECS); estimates are
marked as such.

## Why it matters

Under the 200 road user stress load the main thread spends about 5.7 ms per tick, and through an
emulated headset 27% of frames ran late in one 20 s run, against none in the two 10 s runs just
before the move (same load). The busy junction alone
(23 road users) runs clean. The cost is GDScript touching one object per road user per tick, and
building dictionaries where the ECS should read columns.

## Optimisation, most valuable first

1. **Road-user state as packed columns, not one `AgentState` object per road user**
   (`sim/agent_state.gd`, `sim/traffic_pipeline.gd`, `sim/agent_logic.gd`,
   `shell/traffic_view.gd`, `sim/detection.gd`).
   - **Today:** each tick commits a new state object per road user with 21 copied fields; begin,
     draw, and contacts read the objects again.
   - **Change:**
     - Split the agent into a dynamic `AGENT` component of packed columns (state, progress, speed,
       lane, upcoming, timers, flags, pose) and a static `AGENT_CONFIG`.
     - Commit writes fresh columns, swapped in whole by a `Delta.write_column`.
     - The view copies the pose columns straight into the multimesh buffer.
   - **Estimate:** commit 1.5 to about 0.6 ms, begin 1.4 to about 0.8 ms, draw 1.3 to about
     0.6 ms.
2. **Lane rules scan every road user per priority lane** (`sim/lane_rules.gd`,
   `sim/traffic_pipeline.gd`).
   - **Change:**
     - Bucket road users by lane once per tick.
     - Bake each lane's meeting point and its offset on each priority lane.
     - Use a road user's own progress instead of projecting it.
   - **Estimate:** the largest share of begin; lanes times road users becomes about road users.
3. **Route table built at bake** (`traffic/traffic_snapshot.gd`).
   - **Today:** a `Route` object per lane in use is created and filled every tick.
   - **Change:** build the static table at bake, and fill only the light, give way, and crossing
     flags per tick.
4. **Workers still read shared objects** (`sim/agent_thinker.gd`, `traffic/traffic_sensor.gd`,
   `traffic/traffic_snapshot.gd`).
   - **Today:** thinking reads about 15 members of the shared `Route` and the sensor's `Leader`
     buffers, each through the engine's object validation.
   - **Change:**
     - Flatten routes into packed arrays by lane slot.
     - Have the sensor return a hit index with the gap in a thinker field.
     - Alias the snapshot arrays once per task.
   - **Effect:** thread scaling. Unmeasured: whether sampling a shared `Curve3D` pays the same
     validation.
5. **`World.apply` builds an Array per write** (`ecs/delta.gd`, `ecs/world.gd`).
   - **Change:** iterate the parallel arrays directly and cache the store across consecutive writes.
6. **`ExamLogic` rebuilds dictionaries and copies growing state** (`sim/exam_logic.gd`,
   `rules/rule_frame.gd`).
   - **Today:**
     - The session's faults and dedupe table are copied every tick and grow with the attempt; the
       dedupe table is never pruned.
     - Rules are re-sorted every tick.
     - Every rule state is written whether changed or not.
     - The frame rebuilds a table of 220 road users.
   - **Change:**
     - Alias columns.
     - Copy on report only, and expire dedupe entries past the window.
     - Drop the sort, since rules are spawned in order.
     - Write only changed values.
7. **`CarState.read` runs four times per tick** (`sim/car_state.gd`).
   - **Change:** read it once after the vehicle stage and share it.
8. **`TrafficView.draw` copies its buffer and static data every tick** (`shell/traffic_view.gd`).
   - **Change:** swap the two buffers instead of duplicating, and cache size and colour per slot.
9. **`sorted_ids()` copies and sorts on every call** (`ecs/component_store.gd`).
   - **Change:** cache the sorted ids per store, invalidated on add and remove, or iterate rows
     where row order is already deterministic.
10. **Small systems build a dictionary per row** (`sim/vehicle_logic.gd`, `sim/light_logic.gd`,
    `sim/source_logic.gd`, `sim/detection.gd`).
    - **Change:** alias columns and write only what changed.
11. **Scheduling overhead** (`ecs/world_runner.gd`).
    - **Change:** keep the sorted stage list instead of sorting it every tick.

## Modularisation

12. **The lane's crossing warning always fired**: it checked a removed method. Done: it checks
    for a crossing zone.
13. **Dead code from the old runtime.**
    - Removed: `TriggerZone.contains_point`, the `ParkingBay` geometry queries, the layer groups,
      and `Episode`'s object form.
    - Still present:
      - `AgentState.copy`;
      - `TrafficLight.is_red_state` (duplicating `LightLogic.is_red`);
      - `LaneData.tangent_at` and `has_rules`;
      - `World.has_component`;
      - the `Schema.LANE` component, written but never read (the lanes resource is the source).
14. **A road user's components are built in three places** (`shell/bake.gd`,
    `sim/simulation.gd`, `sim/source_logic.gd`), and a lane in two (`Bake.lane_of`,
    `Simulation.add_path`, which leaves `inverse` unset).
    - **Change:** one `AgentLogic` constructor and one `LaneData` constructor.
15. **Helpers in the wrong module.**
    - `LaneRules.agents_of` belongs with the schema queries.
    - `Bake.ground_direction` belongs in `Geo`.
    - `TrafficLane._half_depth` duplicates `TriggerZone.box_data`.
    - `&"lanes"` is a raw key without a `Schema` constant.
16. **Doc comments that did not match the code.** Done: the five found are corrected.
17. **`AgentThinker.think` is long** (70 lines), and its configuration copy repeats
    `AgentConfig` by hand.
    - **Change:** split it into speed, braking, and lane change parts. With item 1, the thinker
      becomes a batch worker over column slices.
18. **`TrafficView` never releases a removed road user's slot or body.** Nothing despawns road
    users today; a despawn would leave them drawn and solid.
19. **Rules run on dictionaries.** Each tick a rule allocates a `RuleResult` and a new state and is
    called by name.
    - **Change:** acceptable at about 20 rules; when it matters, return the same state when
      unchanged and bind each rule's step as a `Callable` at bake.

## Author decisions

