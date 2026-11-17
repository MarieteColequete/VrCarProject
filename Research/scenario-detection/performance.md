# Performance: road users on worker threads, engine threads

Measured 2026-11-17 on an AMD Ryzen 9 7900X3D (12 cores, 24 threads), Linux, Godot 4.7.2, Jolt.

## Method

- **Headless traffic benchmark** (`TESTS_FILTER=bench`, `tests/cases/bench_test.gd`):
  - 200 reactive road users on ten looping 400 m lanes, 20 per lane, with a cycling light each;
  - a 40 s warm-up, then 600 physics ticks at a fixed 60 fps;
  - per tick it reads the `TrafficSystem` timers and `Performance.TIME_PHYSICS_PROCESS`.
- **Rendered frame run** (a scratch script; not kept):
  - the busy junction plus 200 stress road users, 1280x720, vsync off;
  - 25 s warm-up, then 10 s of frames, giving the mean and 99th percentile frame time.

## Findings

- **Before.** Thinking on the main thread cost about 3.1 ms of agent work per tick for 200 road
  users, most of it the physics shape casts (2.4 ms). The whole physics tick took about 7 ms
  against 0.7 ms without them.
- **Geometric sensing.** A sweep against a snapshot of oriented boxes, with no physics queries,
  costs about 2.7 ms of thinking for 200 road users single-threaded (a profile of thinking alone).
  The scaling run below measured 3.3 ms for one task: the same work, with the thread pool's
  dispatch.
- **Contention.**
  - The first parallel version took 58 ms per tick, slower than single-threaded.
  - The cause was threads sharing GDScript objects. Every read of a shared reference-counted
    object, and every read of a node from an array (which validates it in the object database
    under a lock), queues the threads on one another.
  - Flat packed arrays and integer instance ids fixed it.
  - Thinking then scales to about eight tasks (3.3 ms to 1.0 ms) and degrades past that, so the
    system caps at eight.
- **Pipelining.** Thinking runs through the rest of the tick and is applied at the start of the
  next one.
  - Headless, there is no frame to overlap with, so the main thread waits about 1.4 ms.
  - Rendered, the wait disappears behind rendering.
- **Main thread traffic cost** at 200 road users, from the benchmark's system timers:
  - inline: 4.2 ms for the snapshot and the thinking together (about 0.6 ms of snapshot and the
    rest thinking), plus 0.5 ms applying;
  - parallel: 0.6 ms snapshot, plus 0.7 ms applying.
- **Engine.** The engine's own work moving 200 bodies is about 3.8 ms of the headless tick. The
  separate physics thread takes it off the main thread.

## Rendered frames, 200 stress road users plus the busy junction

Frame time here is wall time between rendered frames in a flat window, which the HUD's "main"
readout (main thread process time) is not.

| Setup | Frame mean | Frame p99 | Frames per second |
|---|---|---|---|
| Single-threaded traffic, single-threaded engine | 9.53 ms | 14.95 ms | 105 |
| Traffic on worker threads | 7.19 ms | 12.13 ms | 139 |
| Traffic on worker threads, physics and render threads | 4.57 ms | 10.08 ms | 219 |

At 90 Hz a frame has 11.1 ms. Before, the slowest frames missed it (p99 14.95 ms); now they fit
(p99 10.08 ms).

## Open

- The separate render and physics threads are verified headless and in a flat rendered run, not
  in a headset. If OpenXR shows a problem, `rendering/driver/threads/thread_model` and
  `physics/3d/run_on_separate_thread` in `project.godot` revert on their own.
