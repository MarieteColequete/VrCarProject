# Performance: road users on worker threads, engine threads

Measured 2026-11-17 on an AMD Ryzen 9 7900X3D (12 cores, 24 threads), Linux, Godot 4.7.2, Jolt.

## Method

- **Headless traffic benchmark** (`TESTS_FILTER=bench`, `tests/cases/bench_test.gd`):
  - 200 reactive road users on ten looping 400 m lanes, 20 per lane, with a cycling light each;
  - a 40 s warm-up, then 600 physics ticks at a fixed 60 fps;
  - per tick it reads the `TrafficSystem` timers and `Performance.TIME_PHYSICS_PROCESS`.
- **Rendered frame run** (a scratch script; not kept):
  - the busy junction plus 200 stress road users, 1280x720, vsync off;
  - 25 s warm-up, then 10 s of frames, giving the mean and 99th percentile frame time;
  - rendered on the processor's integrated Radeon graphics: inside the development container the
    NVIDIA Vulkan driver manifest points at the host's library path, so the loader skipped the
    discrete GPU. The OpenXR run below corrects for this.

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

## Emulated headset, OpenXR through Monado

Measured 2026-11-17, same machine, on the NVIDIA GeForce RTX 4090.

### Method

- **Runtime.** Monado 21.0, the open source OpenXR runtime (Ubuntu 24.04 packages
  `monado-service` and `libopenxr1-monado`), with its simulated headset, which turns the head on
  its own (`SIMULATED_ENABLE=1 SIMULATED_ROTATE=1`). Its compositor draws both eyes in a Wayland
  window and paces frames at 90 Hz (`XRT_COMPOSITOR_FORCE_WAYLAND=1`,
  `XRT_COMPOSITOR_DEFAULT_FRAMERATE=90`); eyes are 896x1007, the simulated headset's default.
- **GPU.** Monado and Godot both run on the discrete GPU through a corrected copy of the NVIDIA
  driver manifest, passed in `VK_DRIVER_FILES`. Without it both fall back to the integrated GPU,
  where Monado's window cannot create its swapchain and the service aborts.
- **Godot.** `XR_RUNTIME_JSON=/usr/share/openxr/1/openxr_monado.json` (the first runs also
  passed `--xr-mode on`, before the project enabled OpenXR). The session reaches visible and
  focused, and `DriverView` switches to the headset camera.
- **Commands**, from the repository root, `<manifest>` being the corrected NVIDIA manifest:
  - `VK_DRIVER_FILES=<manifest> SIMULATED_ENABLE=1 SIMULATED_ROTATE=1
    XRT_COMPOSITOR_FORCE_WAYLAND=1 XRT_COMPOSITOR_DEFAULT_FRAMERATE=90 monado-service`, fed a
    standard input that stays open (Monado polls it and exits when it is closed);
  - `VK_DRIVER_FILES=<manifest> XR_SCALE=2.2 godot --path 'vr-project-[car-sim]' -s
    res://tests/xr_check.gd`.
- **Load.** The busy junction plus 200 stress road users (223 in all); 15 s warm-up, then 30 s of
  frames (2700). Each thread setting is set in a temporary `override.cfg`, so `project.godot` is
  unchanged.
- **Measure.** The runtime paces every frame, so the mean is always 11.11 ms. What differs is how
  many frames run late: frames longer than 1.5 times the 11.1 ms budget, which a headset would show
  as a repeated or reprojected frame.
- Each setup ran twice at the simulated headset's eye size, then twice at 2.2 times it, 1971x2215
  per eye, about a current headset's. The multiplier is a property of `OpenXRInterface`
  (`render_target_size_multiplier`), not a project setting, so `tests/xr_check.gd` sets it from
  `XR_SCALE`.

### Results, 896x1007 per eye

| Render thread | Physics thread | Late frames, run 1 | Late frames, run 2 | Frame p99 |
|---|---|---|---|---|
| Separate | Separate | 11 (0.41%) | 5 (0.19%) | 16.0 to 16.4 ms |
| Separate | Main | 23 (0.85%) | 10 (0.37%) | 16.3 to 16.6 ms |
| Main | Separate | 35 (1.30%) | 12 (0.44%) | 16.4 to 16.8 ms |
| Main | Main | 143 (5.30%) | 73 (2.70%) | 17.2 to 17.4 ms |

### Results, 1971x2215 per eye

| Render thread | Physics thread | Late frames, run 1 | Late frames, run 2 | Frame p99 |
|---|---|---|---|---|
| Separate | Separate | 15 (0.56%) | 37 (1.38%) | 16.5 to 16.9 ms |
| Separate | Main | 89 (3.30%) | 147 (5.44%) | 17.2 to 17.3 ms |
| Main | Separate | 42 (1.56%) | 22 (0.81%) | 16.6 to 16.9 ms |
| Main | Main | 133 (4.92%) | 108 (4.00%) | 17.2 to 17.3 ms |

### Reading

- Every setup holds 90 Hz through the real OpenXR frame loop: waiting for the frame, predicting the
  head pose, rendering both eyes, and submitting.
- At the small eye size, both threads together run the fewest late frames, and neither thread the
  most, in both runs; each thread helps on its own.
- At the headset eye size, the physics thread carries the gain: 0.6% to 1.6% late frames with it,
  3.3% to 5.4% without. The render thread shows no consistent gain there; its runs overlap those
  of the safe mode.
- The spread between runs reaches two times, so the order counts, not the exact numbers.
- During the session neither setting logs an error.
- **At exit, the separate render thread aborts the process** (exit code 134, a core dump). Godot
  frees rendering resources from the main thread while the render thread owns them ("can only be
  called from the render thread", in `free_rid` and `finalize`), after the OpenXR session has
  ended. It happens with every separate render thread run and with none of the others. Godot
  itself warns at start-up that the separate render thread is experimental.

### The exit abort

- **Godot's bug.** [godotengine/godot#119000](https://github.com/godotengine/godot/issues/119000)
  (open; reproduced on 4.6.1 and 4.7; the same in 4.8 as
  [#124799](https://github.com/godotengine/godot/issues/124799)).
  - The render thread takes ownership of the RenderingDevice, and shutdown destroys the device on
    the main thread without handing it back.
  - Flat, this is an error message. Under OpenXR, the session's swapchain textures are also freed
    on the main thread after the render thread has stopped, and the process aborts.
  - A fix, [#123391](https://github.com/godotengine/godot/pull/123391), is open with changes
    requested; an earlier one, [#125339](https://github.com/godotengine/godot/pull/125339), was
    closed. Both were checked 2026-11-17.
- **Side effect.** Reported on the issue: the shader pipeline cache is not saved at exit, so
  shader compilation stutter can return on every launch.
- **No script-level workaround.**
  - Turning `use_xr` off and calling `uninitialize()` on the interface before quitting does not
    end the session: `xrEndSession` still runs in the engine's teardown, and the abort is the same
    in every run.
  - Ending the session cleanly needs `xrRequestExitSession`, which Godot 4.7 does not expose to
    GDScript, only to native extensions.

### What the emulator cannot show

- A headset runtime's own compositor, such as SteamVR's or a Quest's, with its reprojection and
  timing; Monado paces like a desktop runtime.
- How the motion feels: judder and latency are judged by eye, in a headset.

## Open

- **The separate render thread aborts at exit under OpenXR**, until Godot's fix lands, and at the
  headset eye size it shows no consistent gain over the safe mode. Reverting
  `rendering/driver/threads/thread_model` to `1` (safe) removes the abort; the separate physics
  thread, which carries the gain, has no such problem.
- **Controller bindings.** The action map is Godot's stock map, taken unchanged from the
  `driving-mechanics` branch; the motion controllers are not bound to driving.
- **A real headset run** remains for the feel and the headset runtime's own timing.
