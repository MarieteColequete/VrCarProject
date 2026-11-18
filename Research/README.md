# Research

Internal working material and cold storage, optimised for resuming work after a session reset. Not
public-facing: the public documentation stays in `README.md` and `CLAUDE.md`. The format rule is
`.claude/rules/preset/research-cache.md`; the procedure is the `research-topic` skill.

## Topics

| Topic | Folder | Status |
|---|---|---|
| Scenario detection | `scenario-detection/` | Phases 1 to 7 built, and the multicore run (`performance.md`) |
| Multithreaded Godot and VR | `godot-threading-vr/` | State of the art against our measurements; five questions decided, the reference space open |
| Code quality | `code-quality/` | Review of the functional ECS runtime, prepared for a later pass; the road-user columns and a few fixes acted on |

## Open flags for the author

- The `consistency` reviewer's drift list holds only the engine pin; the other settled
  boundaries (physics, input through the OpenXR action map, state ownership) are not decided yet.
- `.allowed_signers` lists one maintainer's key; the other contributors' keys and the signature
  check are not set up.
- The main paper is planned; `CLAUDE.md` names it once it exists.
- `car.gd` on `driving-mechanics` reads raw keys and has its own mouse look and `XROrigin3D`; on
  merge it reads `DriverInput` and carries a `DriverView` instead, so keyboard, gamepad, and VR
  share one set of bindings and one camera rig.
- The physics thread and the Safe render model are verified headless and through Monado, an
  emulated OpenXR runtime, not in a real headset; measurements in a release build and a real
  headset are parked until much later (`godot-threading-vr/brief.md`).
- The motion controllers are not bound to driving; the action map is Godot's stock map.
- The reference space stays Stage with `DriverView` recentring; Godot recommends Local for racing
  simulators (`godot-threading-vr/analysis.md`, section 7). Not decided.
- The `driving-mechanics` branch sets `rendering_device/driver.windows="d3d12"`; this branch uses
  Vulkan on Windows, as Godot's XR team recommends for XR (`godot-threading-vr/sources.md`, B26),
  so the merge takes this branch's line.
- The car control layout is still to be agreed; a wheel's full-range steering axis and pedals may
  need actions of their own.
