# Brief: multithreaded Godot and VR in Godot

The state of the art on Godot 4.x threading and OpenXR, as of 2026-11-17, set against the
project's own measurements. Sources in `sources.md`; the comparison in `analysis.md`; our numbers in
`../scenario-detection/performance.md`. Bounding decisions: Godot 4.7, Forward Plus, Jolt
(`CLAUDE.md`) at the time of writing; the author decisions below changed the renderer and the render
thread.

## Findings that drive the design

- **Traffic threads.** The documented contention causes match ours: the ObjectDB spinlock, refcount
  atomics, and the typed-array thread guard (A15, A16, A17). No external benchmark was found for this
  pattern. All our timings are from a debug build (C1, A18).
- **Reproducibility.** Fixed-order traffic is deterministic. Jolt event order under several worker
  threads is not guaranteed (A19, A20).
- **Physics thread.** The gain is ours alone (no XR source). It is experimental (A11). A 4.7.2
  stall with `_integrate_forces` (A9) does not touch current code.
- **Render thread.** Experimental, with open crash bugs (A1, A7). Field reports show it worse or
  stuttering under XR runtimes (B13, B14). No late latching in 4.7.2 (B1). The pipeline cache is
  lost at exit (A7). The XR lead expects it to become the default (A8).
- **Tick against display.** Godot's XR guidance is a tick equal to the refresh rate (B7) or
  physics interpolation, XR-safe since #106109 (B4, B5). We run 60 Hz without interpolation under
  90 Hz.
- **Renderer.** Godot recommends Mobile for XR (B6), against the Forward Plus pin.
- **Seated reference.** Godot recommends Local for racing (B8); we use Stage and `center_on_hmd`.
  Godot does not quit on the runtime's exit request (B1, B10); we do not handle it.

## Open questions

| Question | Options | Evidence | Status |
|---|---|---|---|
| Q1. Render thread | Keep; keep with kill on quit; keep with a native exit extension; return to Safe [revises a decision]; wait for PR #123391 | A1, A7, A8, B1, B9, B10, B13, B14, B18, B26; performance.md | DECIDED |
| Q2. Smooth world motion at 90 Hz | Keep 60 Hz; physics interpolation; 90 Hz tick; both | B4, B5, B7, C1 | DECIDED |
| Q3. Reproducibility claim | Narrow to traffic; repeat-run test; one worker thread in tests | A8, A19, A20 | DECIDED |
| Q4. Renderer for XR | Keep Forward Plus; Mobile [revises a decision] | B6, B26 | DECIDED |
| Q5. Reference space and runtime exit | Keep Stage with `center_on_hmd`; Local plus `pose_recentered`; and, separately, quitting on `instance_exiting` | B1, B8, B10, C1, C2 | DECIDED (exit); OPEN (reference space) |
| Q6. Measurements still missing | Release export bench; real headset run with reprojection; motion smoothness by eye | A18, B13, B15, B16, B21, B22 | DECIDED |

Dependencies: Q2 changes what a real headset run (Q6) has to judge. Q1 and Q4 interact, since the
render thread's cost depends on the renderer.

## Author decisions

Taken 2026-11-17; the questions above stay as asked, for backtracking.

- **Q1, render thread:** back to Safe (`thread_model=1`). The exit abort is gone with it; no kill
  or native workaround.
- **Q2, world motion:** the world ticks at a fixed 60 Hz, and rendering follows the headset's
  output rate, with physics interpolation between ticks.
- **Q3, reproducibility:** best effort. Traffic is reproducible by construction; physics event
  order under several worker threads is not guaranteed and is not enforced.
- **Q4, renderer:** Mobile. The game is VR only, for PC VR and standalone headsets, and standalone
  headsets need Mobile. This revises the Forward Plus pin.
- **Q5, exit:** the game quits when the runtime asks the application to close
  (`instance_exiting`). The reference space was not decided and stays Stage.
- **Q6, measurements:** parked until much later.
- **Graphics API on Windows:** Vulkan (`rendering_device/driver.windows`), as recommended for XR
  (B26), in place of D3D12.

