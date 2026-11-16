# Research

Internal working material and cold storage, optimised for resuming work after a session reset. Not
public-facing: the public documentation stays in `README.md` and `CLAUDE.md`. The format rule is
`.claude/rules/preset/research-cache.md`; the procedure is the `research-topic` skill.

## Topics

| Topic | Folder | Status |
|---|---|---|
| Scenario detection | `scenario-detection/` | Milestone 1 built; roadmap in six phases; four questions open |

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
- The car control layout is still to be agreed; a wheel's full-range steering axis and pedals may
  need actions of their own.
