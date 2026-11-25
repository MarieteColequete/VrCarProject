# Changelog

## Unreleased

### Fixed

- Start the engine and drive with a Logitech G29 under G HUB, which read its D-pad as the shifter in D, so the key was refused in gear and the throttle did nothing; the shifter's D is now fifth gear
- Look straight ahead with a wheel and no headset, the view no longer turned to the bottom right by the wheel's resting pedals, which also drifted the menus' focus
- Stay on the scenario when a G29's shifter goes into first gear, the same button as the D-pad's down

## v0.6.0-alpha - 2026-11-24

### Changed

- **Breaking:** Drive without the `hill_road` map and its `hill_start` scenario, removed with the roll-back check and fault only it used
- Bump into the signs, traffic lights, cones, and decoration of the exam maps, now solid map assets the Map Kit can change
- Drive a Logitech G29 in its native or PS3 mode, pedals, paddles, and shifter included, with the transmission no longer a setting

### Added

- Start the game on a main menu, and pause, set options, pick a scenario, and read its briefing and result on menus that work in VR
- Follow the way on a GPS tablet held out from the dash: a heading-up map, the route to the goal, the current step, and the distance left
- Hear the engine start with its key, sputter out when the key is let go too soon, and the key click when a start is refused in gear
- Turn loose models into map assets, and find solid things standing in the way of lanes and road users, from the Map Kit's Problems and Selection

### Fixed

- Drive on hand-drawn roads that hills no longer bury, the land flattening under them as under the kit's roads

## v0.5.1-alpha - 2026-11-23

### Fixed

- Place terrain shapes, signs, zones, and models with the Map Kit, whose arming failed with an error in the editor for every piece but roads and junctions
- Move, delete, or undo roads and terrain shapes in the editor without an error about a freed lambda capture in the Output
- Open the project with no GDScript warnings in the editor's Output

## v0.5.0-alpha - 2026-11-23

### Changed

- **Breaking:** Point scenarios and maps at `scenarios/scenes/player_car.tscn` for the player's car, which replaces `debug_car.tscn`; the main scene is now the scenario sandbox
- Drive a car with real tyres, weight transfer, suspension, and a powertrain, shared with the road users, forgiving under the exam aids and sharper in the sport and sim presets
- Feel the car pitch, roll, and follow slopes, the view fixed to the cabin so the world tilts around the driver
- Steer the front wheels by the rack's geometry alone, so turning the wheel never moves a standing car and no aid turns the wheels on its own
- Shift an automatic lever from D through N to R, with park on a button of its own, or step through a manual gearbox
- Start the engine with the key, and stall it by forcing a gear against the car's motion or lugging a manual
- Ease the throttle open on the keys as a foot would, so the automatic settles in top gear at a steady speed and kicks down only when the pedal is held through
- Read the speed, revolutions, gear, lamps, and warnings from the car's own sensors, so a car in the air shows what its wheels turn at, not how fast it falls
- Hear tyres scrub, squeal, and skid only as they slide, with each surface rolling and sounding its own on asphalt, grass, and dirt
- Orbit and zoom the chase view with the mouse or right stick
- Turn the car's steering wheel 900 degrees lock to lock, two and a half turns as on a road car and most sim wheels, instead of 300
- Use one control layout on every device: the gamepad's, matched one to one by the VR controllers and a steering wheel, with the arrow keys and the D-pad tilting the picked mirror and the indicators on the D-pad
- Set the mirrors while driving, not only parked
- Go to the next scenario, or in free drive the next map, with one key (N, D-pad down)
- Free the mouse with Backspace, Escape and Start being kept for a menu to come

### Added

- Build hills, valleys, ramps, and plateaus with a map's terrain, and drape roads onto the land from the Map Kit
- Shape terrain in the editor with outlines and handles in the 3D view, or sliders in the dock, the land following the mouse
- Read fuel and coolant gauges and engine, oil, battery, ABS, stability, and low fuel lights on the instrument cluster behind the wheel
- Be judged on a hill start in the `hill_start` scenario on `hill_road`, with a fault for rolling back
- Learn to build land in the map guide's new terrain chapter
- Drive with a steering wheel: its rim turns the car's wheel 1:1 and its pedals calibrate in `user://controls.cfg`, and in VR holding its rim lines the car's wheel up with it
- Use a Valve Index's controllers with their own bindings
- Read the new driving guide, with every control on PC, controller, VR, and wheel; the controller, VR, and wheel layouts are not yet tried on the hardware

### Fixed

- Light each outside blinker on its own side of the car
- Cut the land just under every road on a slope, instead of burying the asphalt
- Rebuild the land under a road or junction that is moved or deleted in the editor
- Draw the front wheels at the angles they steer, and release road users' bodies when they leave

## v0.4.0-alpha - 2026-11-22

### Changed

- Drive through a five speed automatic gearbox, with steering that eases with speed and a car that turns along its front wheels
- Watch the whole car dip under braking, squat under acceleration, and roll out of a turn, cockpit included, while the head stays level
- Be judged on mirror checks by where the driver looks, eyes or head, held for a moment within the mirror's cone, optionally with the interior mirror and too long a look away from the road
- Read the engine's revolutions and the gear on the instrument panel, with needles that settle without overshooting

### Added

- Look in an interior mirror and two door mirrors that show what a real mirror there would, on the car's own glass
- Set each mirror by gripping it in VR, or with the mirror switch, Tab or the gamepad's d-pad up, kept between sessions
- Steer by gripping the steering wheel's rim with one or both hands in VR
- Drive with the motion controllers: triggers, buttons, and sticks for the throttle, brake, handbrake, headlights, indicators, and recentring
- Hear the engine, the indicator's tick, the tyres near their grip, and a thump on the kerbs
- Feel the controllers buzz on the indicator, a gear change, and a kerb
- Show an instructor a chase or shoulder view on the desktop while the driver is in the headset
- Sit in a textured cabin: cloth seats, leather bolsters and steering wheel, carpet, a felt headliner, and grained plastic
- See dipped beams cast on the road by the headlights

## v0.3.0-alpha - 2026-11-22

### Changed

- **Breaking:** Keep maps apart from scenarios: a map is a scene of its own under `maps/`, found by scanning the folder, and a scenario instances its map and adds only its checks and steps
- Drive the Kiri '86, with rolling wheels, a turning steering wheel, and lights that follow the car's state
- Read the speed, the indicators, and the handbrake, headlights, and reverse tell-tales on an instrument panel inside the car, since the view is VR
- Meet pedestrians that stand idle or walk, animated from the Animated Characters (Retro) survivors
- Mount a kerb only with a tyre: pavements and kerbs are solid, and a tyre touching or crossing a kerb line is judged from its side, front, or back

### Added

- Drive any map alone in free drive, and move from map to map in the sandbox with M
- Build maps in the editor with the Map Kit dock: create, open, check, fix, and play maps, and add roads, lanes, markings, lights, signs, and zones from a palette, all with undo
- Furnish maps from the Asset Library with Kenney's Car, City, and Train kits: favourites, recent models, filters, search, rendered thumbnails, and drag and drop into the view
- Add asset packs by dropping a folder of models with a pack file into `assets/`
- Send selected cars as road users that drive to a checkpoint along a route worked out from the lanes
- Try maps with a Dev HUD: a free camera, time scale, pause and step, and spawn to spawn
- Switch the headlights with L or the gamepad's X
- Learn map making from a guide with screenshots, written for readers new to Godot

## v0.2.0-alpha - 2026-11-18

### Added

- Drive a basic car in a test scene: accelerate, brake, reverse, and steer with the arrow keys or WASD, looking around with the mouse

## v0.1.0-alpha - 2026-11-18

The first version: driving exam scenarios judged as in the exam, played in a VR headset.

### Added

- Drive a stop junction scenario that judges stopping at the line, the speed limit, lane keeping, and contact
- Be judged on crossing solid lines, changing lanes without indicating, riding on lines, and mounting kerbs
- Drive through traffic lights, judged on red and on amber when there was room to stop
- Give way to pedestrians at crossings, without stopping on them
- Overtake a slow vehicle, judged on following distance and on mirror and shoulder checks
- Turn out of a give way junction, judged on giving way, hesitating, indicating, and taking the right turn
- Drive through a roundabout, judged on giving way to circulating traffic, signalling on leaving, and taking the right exit
- Park in bay and parallel parking scenarios, judged on the bay chosen and on the manoeuvre
- Follow scenarios made of ordered steps, each with its own goal
- Share the road with scripted cars and pedestrians, traffic lights, and seeded parked cars
- Meet road users that keep to their script until forced to react: they follow, stop, give way, wait at lights and crossings, and change lanes round a blocked lane where the markings allow
- Be judged on forcing another road user to brake hard
- Drive a busy junction with flows of reactive traffic, lights, a crossing, and a side road
- Run heavy traffic across cores: road users think on worker threads and physics runs on a thread of its own
- Get the same traffic and the same scoring for the same drive: detection and scoring work on geometry, not physics queries
- Run the world at a fixed 60 Hz tick, drawn smoothly at the headset's own refresh rate
- Get a scored result when a scenario ends, with every fault and whether the attempt passed
- Score faults by configurable severity tiers and pass limits instead of a fixed exam
- Pick scenarios from a catalogue giving each one's title, category, and difficulty
- Build new scenarios on a shared base scene, with editor warnings and zones coloured by role
- Try any scenario in a sandbox with a debug overlay showing the briefing, step, time, faults, and result
- Play in a PC VR or standalone headset through OpenXR, and close the game from the headset's runtime
- Test without a headset in a flat view, with a keyboard and mouse or a gamepad, looking around with the mouse or the right stick
- Rebind every control in the project's input actions, without code changes
- Run headless tests of the scoring, the controls, and scripted drives through the scenarios
- Check the game through an OpenXR runtime, such as an emulated headset, with a report of late frames
- Work with the Claude Code agent configuration from claude-preset 0.8.1-alpha, with its rules, skills, and hooks
- Record the project version in a changelog
