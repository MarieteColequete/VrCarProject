# Analysis: our threading and VR results against the state of the art

Sources are the ids in `sources.md` (A for multithreaded Godot, B for VR); our measurements are in
`../scenario-detection/performance.md`. Facts marked U there are not used as evidence here.

## Criteria

1. **Frame pacing in a headset**: frames delivered within 11.1 ms at 90 Hz, and smooth motion of
   the world seen from the cockpit. Universal for PC VR: a late frame is shown as a repeated or
   synthesised one (B21, B22), and judder of the surroundings is a known cause of discomfort
   (B23).
2. **Stability**: no crash or hang in play or at exit. Universal: a crash loses the player's state
   and reads as a defect.
3. **Reproducible attempts**: the same drive scores the same way. Project-specific: the scenario
   tests assert outcomes, and an exam simulator is fair only if a drive is judged the same each
   time; contestable for free driving.
4. **Low maintenance for a small team**: few engine workarounds, no native toolchain unless it
   pays. Project-specific and contestable: the team is small and shares one Godot project, but a
   larger team could carry a toolchain.
5. **Fit with settled decisions**: Godot 4.7, Forward Plus, Jolt (`CLAUDE.md`). Project-specific,
   and by construction it favours the status quo; it records what a change would cost in
   decisions, not whether the change is right. Options that would revise one are marked
   **[revises a decision]**.

## 1. Road users on worker threads

**Ours.**
- A snapshot of flat packed arrays, a high-priority group task, and decisions applied in a fixed
  order next tick.
- Sharing RefCounted objects and reading nodes from arrays made threads contend; ids and packed
  arrays fixed it.
- Thinking scales to about eight tasks.
- A typed `Array[ScriptedAgent]` append failed off the main thread.

**State of the art.**
- **Agrees.**
  - The contention mechanisms are documented in the engine: the global ObjectDB spinlock on every
    object validation (A16) and the shared refcount atomics (A17, A18).
  - The typed-array failure is the thread guard on `Node::get_script` (A15).
  - The docs' rules (A13) allow exactly what the snapshot does: element reads of arrays that do
    not resize while the task runs.
- **Our own evidence only.** No benchmark of hundreds of threaded GDScript agents was found; A21 is
  about bypassing nodes through servers, without numbers for agents. Our numbers are the only ones
  found for this pattern.
- **Qualifiers.**
  - All our timings come from a debug build (C1). GDScript threading scales better in release
    templates (A18), so the plateau at eight tasks may move in an exported build.
  - The pool is shared with Jolt's jobs, which are high priority too (A10), and with the render and
    physics pump threads, which run other pool tasks while they yield (A5). Under load, our
    thinking, Jolt and rendering compete for the same workers, and a dedicated render thread is
    being debated upstream for that reason (A6).

## 2. Reproducibility

**Ours.** Thinking in parallel gives exactly the reactions of thinking inline (`threads_test`), and
`CLAUDE.md` says runs stay reproducible.

**State of the art.**
- Jolt in Godot is repeatable only with the same binary and the same order of calls (A19).
- With several worker threads, contact and area event order can follow thread timing; on 4.7.2,
  multithreaded runs are reported to diverge, and one worker thread restores repeatability (A20,
  causal chain U).
- `call_on_render_thread` timing is also not deterministic (A8).

**Reading.** The traffic layer is deterministic by construction, which agrees with A19's condition
(fixed order of application). The physics layer underneath, the player's car contacts and the
trigger areas the checks use, is not guaranteed to be. The scenario tests have not shown
divergence, but nothing in them would catch a rare reordering. On criterion 3 the claim holds for
traffic decisions and is unproven for physics events.

**Options.**
- **Narrow the claim** to the traffic layer. Gives up nothing, but leaves physics order unproven.
- **Repeat-run test.** Run a scenario several times and compare event logs. It costs test time and
  can only show divergence, not prove its absence.
- **One worker thread in tests** (`threading/worker_pool/max_threads=1`). This makes tests
  repeatable, but gives up testing the threaded configuration the game ships with.

## 3. Separate physics thread

**Ours.** At headset eye size, 0.6% to 1.6% late frames with it, against 3.3% to 5.4% without
(Monado, debug build, two runs each).

**State of the art.**
- **No source measures it in XR**; our numbers are the only evidence.
- **Experimental status.**
  - Jolt's separate thread is "not tested very thoroughly" (A11).
  - Physics API access is limited to the physics process (A1, A5).
  - A 4.7.2 stall with separate-thread physics when forces are applied in `_integrate_forces`
    (A9) is fixed in 4.8 and awaiting a 4.7 cherry-pick. Neither this branch nor
    `driving-mechanics` uses `_integrate_forces` or `VehicleBody3D` today (C2), so it is a risk
    for future car physics, not a present one.
- **What it moves.** Only the `step()` leaves the main thread; `_physics_process` stays, and the
  main thread blocks in `sync()` (A2, A5). The measured gain therefore comes from overlapping the
  step with rendering and the next frame's work. That fits the late-frame drop being largest at
  headset eye size, where rendering is longest.

## 4. Separate render thread

**Ours.**
- No consistent gain at headset eye size.
- At exit under OpenXR the process aborts.
- Killing the process instead closes in 0.09 s with no errors, at the cost of every save at exit
  and an abnormal exit code.
- Kept by decision.

**State of the art.**
- **Against.**
  - It is experimental, with open crash bugs (A1, A7).
  - The shutdown ownership bug has an open fix (A7, B12).
  - On Steam Frame it is measurably worse than Safe, because the runtime blocks in `xrBeginFrame`
    (B13).
  - It caused controller stutter on Quest over Air Link (B14).
  - It can add jitter (B4).
  - In 4.7.2 Godot has no late latching to recover the added pipeline latency (B1).
  - The pipeline cache is reported as not saved at exit (A7), so shader stutter can repeat on each
    launch.
- **For.**
  - The OpenXR code comments that a separate rendering thread suits OpenXR (B1).
  - The XR lead's proposal aims to make it the default, citing a sixfold speedup in one game and
    arguing `xrWaitFrame` offsets the latency (A8).
  - The March 2026 XR update expects gains on standalone (B26).
- **Reading.** Our "no consistent gain at headset size" agrees with the field reports (B13, B14),
  not with the expectation (A8, B26). One possible explanation, not tested: the expected gains are
  argued for CPU-bound scenes and standalone hardware, while ours ran on a desktop GPU with the
  traffic already on worker threads. Our runs are one runtime (Monado), two runs per setup.

**Options.**
- **Keep it** (current decision). Right where the expected gain materialises: CPU-bound scenes or
  standalone hardware (A8, B26), and once the shutdown fix lands. It gives up stability at exit
  (criterion 2), carries runtime-specific pacing risk (B13, B14), and loses the pipeline cache.
- **Keep it, and kill the process on quit.** Right when the render thread stays and a clean close
  is needed now: it removes the abort immediately, needs no toolchain, and is one script call. It
  gives up saves at exit and a normal exit code. B10 asks applications to end their process
  gracefully at EXITING, which a kill does not. Monado treats a killed client cleanly (B18); no
  source was found on how SteamVR or Meta's runtime treat one.
- **Keep it, with a native extension.** Right when the session must end cleanly in the runtime's
  eyes (B9, B10): a GDExtension requests the session exit (B3), waits for STOPPING, then exits the
  process. It adds a native toolchain per platform (criterion 4), and since the swapchains are
  still freed after the render thread stops (B1), the exit itself still has to bypass Godot's
  teardown.
- **Return to Safe** **[revises a decision]**. It removes the abort, the cache loss and the
  runtime-specific pacing risk, and gives up any gain on CPU-bound or standalone targets. Our
  measurements show no consistent loss at headset eye size.
- **Wait for the fix** (A7, PR #123391, open with changes requested). It removes the abort without
  project work, on an unknown timeline.

## 5. Physics tick against the display rate

**Ours.**
- 60 Hz physics, physics interpolation off, 90 Hz display (C1).
- The road users and the car move in the physics tick (C2).

**State of the art.**
- Godot's XR guide sets the tick to the refresh rate, because a mismatch stutters (B7).
- The 4.7 settings recommend physics interpolation when the tick is not a multiple of 60, and say
  racing games may benefit from a higher tick (B4).
- Since PR #106109, interpolation is XR-safe:
  - tracked nodes are kept uninterpolated;
  - XROrigin3D publishes its interpolated transform each frame (B5).

**Reading.** An inference, not a measurement: at 60 Hz under a 90 Hz display, the world would
advance one tick on some frames and none on others, so traffic and scenery would judder relative to
the cockpit. It is inferred from B4, B5 and B7; no source states it for this setup, and the Monado
runs measured frame times, not motion smoothness. The opposing case: the cockpit and the head are
unaffected (the head pose comes from the runtime, B2, B5), so the effect is limited to what moves
past the car, and how visible it is at driving speeds is untested.

**Options.**
- **Keep 60 Hz without interpolation.** Right if a headset run shows the motion acceptable: no
  change, no added latency, tests unchanged. It gives up smoothness if the judder is visible.
- **Physics interpolation.**
  - Smooth motion at any display rate.
  - Gives up up to one tick (16.7 ms) of visual lag on simulated motion.
  - Spawned or teleported bodies need `reset_physics_interpolation` (the traffic source places
    bodies before adding them).
  - Tests are unaffected, since interpolation is visual only.
- **A 90 Hz tick.**
  - Matches the target headset.
  - Costs 1.5 times the physics and traffic work per second.
  - Leaves 120 Hz headsets mismatched.
  - The scenario tests run at a fixed 60 per second and their timings assume it.
- **Both.** A higher tick for vehicle handling with interpolation for display.

## 6. Renderer

**State of the art.** Godot recommends Mobile for desktop and standalone VR, and says Forward+ is not
well optimised for XR yet (B6). The `driving-mechanics` branch already uses Mobile.

**Reading.** The Forward Plus pin differs from Godot's XR recommendation. That recommendation is
generic, not measured for this project. Our Monado runs show only that Forward+ reaches 90 Hz on
an RTX 4090; they say nothing either way about other GPUs.

**Options.**
- **Keep Forward Plus.** Right for a PC-only simulator on capable GPUs, and it keeps the settled
  decision and the measured configuration. The project uses none of its exclusive features today
  (no SDFGI or volumetric fog, C2), so what it keeps is room to adopt them. It gives up the
  renderer Godot tunes for XR, with unknown headroom on mid-range GPUs, and any path to standalone.
- **Mobile** **[revises a decision]**. Right if mid-range PC VR or standalone headsets are targets:
  it is Godot's recommended XR path (B6) and already on `driving-mechanics`. It gives up the
  Forward+-only features, and the measurements would have to be rerun.

## 7. Seated reference and lifecycle

- **Reference space.** The project uses Stage, Godot's default (C1), and `DriverView` recentres
  with `center_on_hmd` (C2). Godot recommends Local for racing simulators: the runtime recentres,
  `pose_recentered` is emitted, and `center_on_hmd` is not called (B8).
  - **Keep Stage with `center_on_hmd`.** Right while it works on the target runtimes: no change,
    and the game controls when it recentres. It departs from Godot's racing guidance and leaves
    recentring to code rather than to the runtime's own control.
  - **Switch to Local.** Right for a seated experience that should follow the runtime's recentre
    button. It needs a `pose_recentered` handler, changes `DriverView`'s recentring behaviour,
    and has not been tried here.
- **Runtime exit.** Godot emits `instance_exiting` and does not quit (B1). The specification asks
  the application to end its process (B10). `DriverView` does not handle it, so closing the game
  from the headset menu leaves it running.
- **Comfort.** A stable cockpit and an earth-fixed horizon reduce sickness in driving simulators
  (B24); brief accelerations and vignetting help (B23). The cockpit is a fixed reference already;
  the horizon depends on the scenery.
- **Headroom.** On PC, foveated rendering under Forward+ is Godot's VRS_XR density map
  (`vrs_min_radius`, `vrs_strength`), not `foveation_level`, which is Meta's extension (B3, B8).
  Glow, bloom and DOF disable it.

## 8. Measurement method

- **The route.** Monado's simulated driver and null compositor exist for exactly this kind of run
  (B18, from its source); the alternatives found are Windows-only or without tracking (B19, B20,
  both U). Godot cannot run OpenXR without graphics until PR #124135 lands (B17). No Godot project
  running OpenXR in CI was found.
- **Runtimes differ in where they block.**
  - Steam Frame's runtime blocks in `xrBeginFrame` (B13).
  - Some runtimes sync in `xrEndFrame` (B16).
  - Unexplained SteamVR spikes are open (B15).
  - Monado's pacing is a third behaviour, so late-frame rates carry over only as an ordering of
    the settings, not as absolute numbers.
- **Not measured.**
  - **Release build.** Debug-build timings understate GDScript threading (A18).
  - **Real headset runtime.** Its reprojection changes what a late frame costs: half rate with
    synthesised frames, worse on non-linear motion such as a turning car (B21, B22).
  - **Motion smoothness.** Section 5 cannot be judged from frame times.
