# Changelog

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
