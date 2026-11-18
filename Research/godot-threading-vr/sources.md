# Sources: multithreaded Godot and VR in Godot

All accessed 2026-11-17. Engine source read at tag `4.7.2-stable` (released 2026-08-18); 4.8 was in
beta. State: **V** read in the primary source, **V2** two independent secondary sources agree,
**U** unverified, not citable.

## A. Multithreaded Godot

| Id | Source | Facts | State |
|---|---|---|---|
| A1 | `doc/classes/ProjectSettings.xml` @4.7.2 | `rendering/driver/threads/thread_model` Separate is experimental, with known crash bugs (particles, window resizing). With physics on its own thread, physics API access is restricted to the physics process. `threading/worker_pool/low_priority_thread_ratio` (0.3) reserves threads for low priority work; `max_threads=-1` uses all logical cores. | V |
| A2 | `main/main.cpp`, `core/config/project_settings.cpp` @4.7.2 | Thread models are Unsafe (deprecated), Safe, Separate; no "single safe". The editor forces Safe. Frame order: physics `sync()`, `flush_queries()`, `_physics_process`, `end_sync()`, queued `step()`, then `RenderingServer.sync()` and `draw()`. | V |
| A3 | godot PR #90268 "Use WorkerThreadPool for Server threads" (merged 2024-04, 4.3) | Rendering and physics servers run as WorkerThreadPool pump tasks; `CommandQueueMT` syncs through the pool's yield. | V |
| A4 | godot PR #98383 (merged 2024-12, 4.4) | Deprecates the unsafe model. | V |
| A5 | `rendering_server_default.cpp`, `physics_server_3d_wrap_mt.cpp`, `worker_thread_pool.cpp` @4.7.2 | Pump loops call `WorkerThreadPool.yield()`; a yielding pump thread runs other queued pool tasks. The physics step runs on the pump thread; `sync()` blocks the main thread until it ends. `space_get_direct_state` fails off the main thread. `_assign_mt_ids` makes the RenderingDevice current on the render thread; `finish()` resets `server_thread` only. | V |
| A6 | godot PR #121941 "Use a dedicated thread for the thread renderer" (open, 2026-07) | Rendering starves and stutters while pool threads are busy; a dedicated thread is proposed; disputed. | V |
| A7 | godot #119000, #124799, #124798, #123417; PR #123391 (open) | Separate: wrong-thread `RenderingDevice::finalize` at shutdown (#119000, 4.6.1 and 4.7); crash on exit in 4.8 beta1 (#124799); MultiMesh interpolation uploads bypass the MT wrapper (#124798); startup crash on 4.7.2 macOS (#123417). The pipeline cache is reported as not saved at exit. | V |
| A8 | godot-proposals#14578 (2026-03) | Proposes Separate as the eventual default, citing a sixfold speedup in one game, and argues `xrWaitFrame` offsets the added input lag; no milestone. One XR user reports `call_on_render_thread` timing is not deterministic. | V |
| A9 | godot PR #117268 (4.7), #123654, PR #124990 (merged 2026-11-02, 4.8, cherry-pick 4.7 pending) | Since 4.7 physics server calls during physics processing run synchronously. #123654: a stall with separate-thread physics (`apply_torque` in `_integrate_forces`) on 4.7.2; fix not in a 4.7.x release yet. | V |
| A10 | `modules/jolt_physics/spaces/jolt_job_system.cpp` @4.7.2; PR #118236 (4.8) | Each Jolt job is a high-priority pool task; Jolt's concurrency equals the pool's threads. 4.8 makes the contact listener lock-free. | V |
| A11 | Godot docs "Using Jolt Physics" (4.7) | Run On Separate Thread is supported but "not been tested very thoroughly". | V |
| A12 | `WorkerThreadPool.xml` and `.cpp` @4.7.2 | `add_group_task` defaults to low priority, capped at `CLAMP(threads * ratio, 1, threads - 1)`. `wait_for_group_task_completion` waits on a semaphore without helping. The docs warn of negative gains for cheap work. | V |
| A13 | Godot docs "Thread-safe APIs" (4.7) | The scene tree is not thread-safe; use `call_deferred`/`set_deferred`. Array and Dictionary element reads and writes are fine, resizing needs a Mutex. One Resource modified from several threads is unsupported. No RenderingDevice section; the line on enabling server thread safety predates 4.3. | V |
| A14 | `Node.xml` @4.7.2 | `process_thread_group` with sub-threads, `call_thread_safe`, `call_deferred_thread_group`. | V |
| A15 | godot #101151; `node.cpp`, `container_type_validate.h` @4.7.2 | Appending to a typed array of a script class validates with `get_script()`, which is thread-guarded on nodes in the tree. | V |
| A16 | `core/object/object.h` @4.7.2; PR #118803 (open), #118507 (closed) | `ObjectDB::get_instance` takes one global SpinLock, used by GDScript object validation; a lock-free version is not merged. | V |
| A17 | godot PR #117850 (merged 2026-03, 4.7) | Removes redundant RefCounted traffic on every GDScript call; that shared atomic contends across threads. | V |
| A18 | godot #58279, #65404; PR #118808 (4.8) | GDScript calls scale poorly across threads, worst in debug builds; one release-template benchmark on 4.7.1 (4 cores, 8 threads) reached about 3.5 to 4.5 times. | V (text); U (generalising) |
| A19 | Jolt docs "Deterministic Simulation" | Determinism needs the same binary and the same order of API calls; contact callbacks and query results arrive in no fixed order; cross-platform determinism needs a build flag Godot does not set. | V |
| A20 | godot-proposals#15750 (2026-11-09) | On 4.7.2 with Jolt, multithreaded runs diverge; `max_threads=1` restores repeatability; traced to contact listener containers filled in thread order (containers confirmed in source). | V (source); U (causal chain) |
| A21 | Godot docs "Optimization using Servers" (4.7) | Server RIDs bypass nodes for tens of thousands of instances; server getters stall asynchronous servers. | V |
| A22 | gdext (godot-rust) docs, `experimental-threads` | Thread support in `Gd<T>` carries a high risk of unsoundness; Rust threads are advised over Godot threads. | U |
| A23 | GECS, godot-ecs (Asset Library) | godot-ecs has a scheduled mode on the WorkerThreadPool; no benchmarks found. | U |

## B. VR in Godot

| Id | Source | Facts | State |
|---|---|---|---|
| B1 | `modules/openxr/openxr_api.cpp` @4.7.2 | `process()` (main thread) polls events and calls `xrWaitFrame`, posting the predicted time to the render thread; a comment says OpenXR works best with a separate rendering thread. `pre_render()` (render thread) calls `xrLocateViews`, `xrBeginFrame`; `end_frame()` calls `xrEndFrame`. No late latching. `destroy_session()` frees swapchains and carries a TODO about a still-rendering render thread. `on_state_exiting()` only notifies; `on_state_stopping()` calls `xrEndSession`. | V |
| B2 | `main/main.cpp`, `rendering_server_default.cpp` @4.7.2 | `XRServer::_process()` runs on the main thread before the physics steps; `pre_render` and `end_frame` run inside the RenderingServer draw. | V |
| B3 | `OpenXRInterface` reference and `openxr_interface.cpp` @4.7.2 | No exit-request method. `foveation_level`/`foveation_dynamic` drive Meta's XR_FB_foveation. `vrs_min_radius`/`vrs_strength` need `Viewport.vrs_mode = VRS_XR`. `OpenXRAPIExtension` exposes `get_session()` and `get_instance_proc_addr()` to extensions. | V |
| B4 | `ProjectSettings` reference @4.7.2 | `thread_model` notes syncing with the main thread "can cause a bit more jitter". `physics_ticks_per_second`: enable interpolation when not a multiple of 60; racing games may benefit from a higher tick. Foveation is disabled with desktop MSAA 3D. | V |
| B5 | `scene/3d/xr/xr_nodes.cpp` @4.7.2; godot PR #106109 (merged) | XRCamera3D and XRNode3D force physics interpolation off; with interpolation on, XROrigin3D sets the world origin from its interpolated transform each frame. | V |
| B6 | Godot docs "Setting up XR" (latest) | Recommends the Mobile renderer for desktop and standalone VR; Forward+ "isn't well optimized for XR right now". | V |
| B7 | Godot docs "A better XR start script" (latest) | Sets the physics tick to the headset refresh rate, since a mismatch causes stutter; the `session_stopping` handler only prints. | V |
| B8 | Godot docs "OpenXR settings" (latest) | Local reference space is the best option for flight and racing simulators; the runtime recentres and emits `pose_recentered`; do not call `center_on_hmd` with Local. Foveation needs VRS_XR and is disabled by glow, bloom, DOF. | V |
| B9 | Khronos OpenXR 1.1, `xrRequestExitSession` | Moves a running session through STOPPING to EXITING. | V |
| B10 | Khronos OpenXR 1.1, `XrSessionState` | On EXITING the application should end its process if it has no non-XR experience; on LOSS_PENDING it should destroy the session. | V |
| B11 | Khronos OpenXR 1.1, `xrWaitFrame` | May be called from any thread; throttles to the frame interval. | V |
| B12 | godot #119000 | As A7; not XR-specific; the issue text concerns `finalize`, not swapchains. | V |
| B13 | godot #124314 (open, 4.7.2) | On Steam Frame, Separate gives worse frame times than Safe (Safe passes "Verified"); attributed to the Valve runtime blocking in `xrBeginFrame`; a contributor recommends calling `xrWaitFrame` late, then late latching. | V |
| B14 | godot #79083 (open) | Separate makes controller tracking stutter on Quest 2 over Air Link. | V |
| B15 | godot #121104 (open, 4.7) | Frame spikes of 20 to 30 ms at 90 Hz under SteamVR, even in empty scenes; Separate helped partly; not reproduced by a maintainer. | V |
| B16 | godot #91945 (closed) | Some runtimes sync inside `xrEndFrame`, blocking Godot's render path. | V |
| B17 | godot PR #124135 (open, draft) | XR_MND_headless support (OpenXR without graphics); not in 4.7.2. | V |
| B18 | Monado source (main): simulated and qwerty builders, `target_instance.c`, `ipc_server_per_client_thread.c` | `SIMULATED_ENABLE`, `QWERTY_ENABLE`, `XRT_COMPOSITOR_NULL`; on client disconnect the IPC server destroys its session and compositor. | V |
| B19 | Meta XR Simulator documentation | OpenXR runtime for Windows and Apple-silicon macOS; Vulkan and D3D; activated through `XR_RUNTIME_JSON` or the registry. | U |
| B20 | SteamVR null driver community guides; Unreal forum (UE 5.7, Linux) | Enabled by `forcedDriver: null`; no tracking; one report of `xrCreateSession` failing headless on Linux. | U |
| B21 | Meta "Asynchronous SpaceWarp" (PC) | A PC app missing 90 Hz drops to 45 Hz and ASW synthesises frames; linear motion predicts better than non-linear. | V |
| B22 | Road to VR and PC Gamer on SteamVR Motion Smoothing | Engages on dropped frames, renders at half rate, synthesises the rest. | V2 |
| B23 | Meta "Locomotion comfort and usability" | Brief accelerations, vignetting, independent visual backgrounds, constant eye height, seated support. | V |
| B24 | Frontiers in VR 2020 (10.3389/frvir.2020.582095); CHI 2004 driving simulator paper | An earth-fixed reference (static horizon, independent visual background) reduces visually induced motion sickness in driving simulators. | V2 (abstracts) |
| B25 | Godot docs "Controllers, gamepads, and joysticks" | SDL 3 input since 4.5; wheels and pedals "less tested"; no force feedback in core. | V |
| B26 | Godot "XR update March 2026" | Recommends Vulkan on Windows for XR; separate-thread safety work in the vendors plugin may help standalone performance. | V |
| B27 | godot #119146 (open), #124496 (closed) | Editor crash on quitting an XR project on macOS; a fixed exit crash with a GDExtension OpenXR wrapper. | V |
| B28 | Asset Library "Godot XR Simulator", "XR Input Simulator" | Keyboard and mouse simulation of the XR camera and controllers, without an OpenXR runtime. | U |
| B29 | GitHub code search for `XRT_COMPOSITOR_NULL` | A few small repositories use it in smoke tests; no Godot project with OpenXR in CI found. | U |

## C. This project

| Id | Source | Facts | State |
|---|---|---|---|
| C1 | Godot 4.7.2 binary reading this project's settings (`ProjectSettings.get_setting`, `OS.is_debug_build`) | `xr/openxr/reference_space` is 1 (Stage, the default; the project sets none); `physics/common/physics_interpolation` is false; `physics_ticks_per_second` is 60; `threading/worker_pool/max_threads` is -1 on 24 logical cores; the editor binary used for every timing is a debug build. | V |
| C2 | This repository and `origin/driving-mechanics`, searched 2026-11-17 | `DriverView` calls `XRServer.center_on_hmd` in `_ready` and `reset_look`; `TrafficSystem` adds its group task with high priority; `DebugCar` is a `CharacterBody3D` moved in `_physics_process`; no code uses `_integrate_forces` or `VehicleBody3D`; no scene or setting uses SDFGI or volumetric fog. | V |
