# Research

Internal working material and cold storage, optimised for resuming work after a session reset. Not
public-facing: the public documentation stays in `README.md` and `CLAUDE.md`. The format rule is
`.claude/rules/preset/research-cache.md`; the procedure is the `research-topic` skill.

## Topics

| Topic | Folder | Status |
|---|---|---|
| Scenario detection | `scenario-detection/` | Phases 1 to 7 built, and the multicore run (`performance.md`) |

## Open flags for the author

- The `consistency` reviewer's drift list holds only the engine pin; the other settled
  boundaries (physics, input through the OpenXR action map, state ownership) are not decided yet.
- `.allowed_signers` lists one maintainer's key; the other contributors' keys and the signature
  check are not set up.
- The main paper is planned; `CLAUDE.md` names it once it exists.
- The `driving-mechanics` branch sets `renderer/rendering_method="mobile"`, against the Forward
  Plus pin in `CLAUDE.md`.
- `car.gd` on `driving-mechanics` reads raw keys and has its own mouse look and `XROrigin3D`; on
  merge it reads `DriverInput` and carries a `DriverView` instead, so keyboard, gamepad, and VR
  share one set of bindings and one camera rig.
- The separate render and physics threads (`project.godot`) are verified headless, in a flat
  rendered run, and through Monado, an emulated OpenXR runtime, at 90 Hz and headset eye size;
  not yet in a real headset. Under OpenXR the separate render thread aborts the process at exit
  (Godot issue 119000, no script workaround) and shows no consistent gain at headset eye size;
  the physics thread carries the gain. `scenario-detection/performance.md` has the numbers.
- The motion controllers are not bound to driving; the action map is Godot's stock map.
- The car control layout is still to be agreed; a wheel's full-range steering axis and pedals may
  need actions of their own.
