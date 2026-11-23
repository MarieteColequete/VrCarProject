# VrCarProject

A car driving simulator for virtual reality, built with Godot 4.7 and OpenXR, that turns the
situations of the practical driving exam into scenarios driven in VR.

## Controls

The simulator is VR only, built for a headset and a driving wheel, on PC VR and standalone headsets.
For development it also runs flat on a monitor with a keyboard and mouse or a gamepad. Bindings are
input actions in `project.godot`, so a device is added or remapped there without code changes; car
scripts read them through `DriverInput`. The one gesture is park on a gamepad: a pad has no button
left for it, so holding `shift_down` for `DriverInput.PARK_HOLD` (half a second) parks, wherever
`shift_down` is bound.

| Action | Keyboard and mouse | Gamepad |
|---|---|---|
| Throttle | W, Up | Right trigger |
| Brake | S, Down | Left trigger |
| Steer | A and D, Left and Right | Left stick |
| Handbrake | Space | A (Cross) |
| Engine: hold to start, press to switch off | Enter | Start |
| Gear lever up, down (the automatic's D, N, R; from P, up is D and down is R; the manual's 6 to 1, N, R) | Shift, Ctrl | B (Circle), D-pad down |
| Park (the automatic) | P | Hold D-pad down |
| Indicators | Q and E | Left and right shoulder |
| Headlights on or off | L | X (Square) |
| Look around; in the chase view, orbit the car | Mouse | Right stick |
| In the chase view, closer, farther | Mouse wheel | |
| Recentre the view; in the chase view, back behind the car | C | Right stick click |
| Set a mirror: interior, left, right, then none; parked only | Tab, then the mouse | D-pad up, then the right stick |
| Driver or chase view; in VR, the spectator's chase or shoulder view | V | Select |
| Free the mouse, recapture it | Escape, click | |
| Begin the attempt after the briefing | Enter | Start |
| Restart the attempt | R | Y (Triangle) |
| Next scenario, in the sandbox | N | D-pad right |
| Next map in free drive, in the sandbox | M | D-pad left |
| Show or hide the debug HUD | F1 | Left stick click |

With the Dev HUD on (see Maps), F3 to F9 drive its tools, as input actions; its free camera flies
with the mouse, W, A, S, and D, Q and E for down and up, and Shift to go faster, keys that are
fixed, not input actions.

`DriverView` is the driver's head in a car scene. With an OpenXR headset running, the headset turns
the view; otherwise the mouse and the right stick turn a flat camera within a seated driver's
range, and its `look_direction()` is the same in both modes.

## Virtual reality

OpenXR is enabled in `project.godot`, with the Mobile renderer, which Godot recommends for XR and
which standalone headsets require. With an OpenXR runtime active and a headset available, the game
starts in the headset and `DriverView` follows the head; otherwise it starts flat for development,
with no alert, and the mouse and right stick turn the view. `--xr-mode off` on the command line
forces flat, for a machine whose active runtime would otherwise launch, such as SteamVR. Closing
the application from the headset's menu quits the game. The action map (`openxr_action_map.tres`)
is Godot's stock map, and `DriverView` turns the motion controllers' inputs into the car's input
actions, so the car reads them as it reads a keyboard or a gamepad:

| Action | Motion controllers |
|---|---|
| Steer | Grip the steering wheel's rim with one or both hands and turn it |
| Throttle | Right trigger |
| Brake | Left trigger |
| Handbrake | Right A |
| Engine: hold to start, press to switch off | Left X |
| Gear lever up, down (the automatic's D, N, R; the manual's gears) | Flick the right stick up or down (down moves the lever when let go) |
| Park (the automatic) | Hold the right stick down |
| Indicators | Flick the left stick left or right |
| Headlights on or off | Right B |
| Recentre the seat | Right stick click, or hold both grips away from the wheel for 2 s |
| Set a mirror | Grip its glass and move the hand across it, or the left stick click, then the right stick |

A grip within 10 cm of the rim takes hold of the wheel there (`WheelGrab`), and the glove is drawn
on the rim while it holds; the wheel turns as the holding hands move round it, the average of the
two with both, and centres itself once let go. The controllers buzz on the indicator, a gear
change, a tyre meeting a kerb, the starter turning, and a stall. The gloves are simple shapes made by the game, on a visual layer
of their own that the mirrors leave out.

On a desktop the window shows an instructor's view while the driver is in the headset
(`SpectatorView`), as Godot's OpenXR spectator demo does: the headset renders a viewport of its own
sharing the world, and the window follows the car from behind and above, or from behind the
driver's shoulder, steadied so it turns with the car but never pitches or rolls; toggle_view (V,
Select) switches between them, and the debug HUD and the Dev HUD draw over it. The headset's camera
hears the car's sound. A standalone headset has no window, and no spectator.

The world ticks at a fixed 60 Hz whatever the headset's refresh rate (commonly 72 to 144 Hz), and
physics interpolation draws every body between ticks at the headset's own rate, so the world moves
smoothly past the cockpit while scoring and traffic stay tied to the fixed tick. The headset
camera is never interpolated: it follows the runtime's pose directly.

`tests/xr_check.gd` runs the busy junction with 200 extra road users through the active runtime,
without `--headless`, and reports the frames that ran late:

```
godot --path 'vr-project-[car-sim]' -s res://tests/xr_check.gd
```

It prints `XR CHECK PASS` or `XR CHECK FAIL` and exits 1 on failure.
`Research/scenario-detection/performance.md` describes running it against Monado's simulated
headset.

## Simulation

The simulation is data and pure functions, detached from what is drawn. Its state lives in a
`World` (`scenarios/ecs/`): entities are ids, and each component is a table of plain columns, such
as the car's motion, a zone's box, a rule's state, or the road users' progress and speeds, one
packed array per field. Systems are static
functions that read the world and return a `Delta` (values to write, entities to add or remove,
events) instead of writing it; nothing else changes the world. Events (`WorldEvent`) are values: a
fault, a reaction, a light changing, the car entering a zone.

A `WorldRunner` runs a tick in a fixed order: it applies the traffic decided on worker threads
during the last tick, reads the car's pose through its `VehicleProbe`, runs the systems in stages,
applies their deltas in order, starts the next traffic work, publishes the tick's events, and runs
the views. The stages (`Simulation`, `scenarios/sim/`) are the car's motion; zones, contacts and crashes;
lights and traffic sources; then the rules and the session. Within a stage every system reads the
same world.

Scenario scenes stay the authoring side: when one loads, a `Bake` (`scenarios/shell/`) reads its
markings, zones, bays, obstacles, lights, lanes, road users, sources, steps, and checks into the
world, every node reference becoming an entity id. Detection is geometry, not physics: the car is in
a zone while its body box overlaps the zone's box, and touches a road user or obstacle while its
contact hull overlaps that body, so the same drive scores the same way on every run. Views draw the
world and touch nodes and servers only: the road users are one `MultiMesh`, interpolated between
ticks, with a kinematic body each in the physics server; the player's car meets walkers there, and
road users' cars only through the crash system (`Impacts`);
lights light their lamps; parked cars are placed once.

Solid things collide by their kind, a `BodyType` (`scenarios/data/body_types/`), one per physics
layer: the ground, pavements and kerbs, obstacles (houses, poles, fences, props), vehicles (parked
cars and road users, on the traffic layer), pedestrians, and the player's car. A type sets the
layer, what it collides with, and the surface's grip and bounce; the player's car reads the grip
under each wheel. Whether it is judged follows its layer: the bake turns the boxes of
obstacles, vehicles, and pedestrians into obstacle entities, which road users see and
`ContactCheck` judges, and leaves pavements out. The player's car is a box riding 0.25 m above the ground, so the bodywork clears a
kerb and may overhang it, and a box for each tyre, which is what a kerb stops. A tyre touching or
crossing a kerb line is judged as hitting the kerb, from its side or, driven straight at it, its
front or back.

## Threads

The simulation is spread across cores. The physics step runs on a thread of its own
(`project.godot`), and Jolt spreads the simulation over its own workers. Rendering stays on the main
thread: Godot's separate render thread is experimental and crashed the game at exit under OpenXR.
Road users think on worker threads: the `TrafficPipeline` copies the road users' columns into an
`AgentTable`, evaluates the lanes' rules into flags over the `RouteTable` (the lanes as columns,
baked once), and takes the bodies into a `TrafficSnapshot` each tick, and runs of rows decide from
them in
parallel while the main thread renders and runs the rest of the tick, and the decisions are committed in a fixed order at the
start of the next tick. They react one tick after they see, and their decisions do not depend on
the threads' timing; with detection and scoring on geometry, scoring is reproducible by
construction, and only the player's own car physics is best effort. The method and the numbers are
in `Research/scenario-detection/performance.md`.

## Models

The cars, trains, houses, shops, factories, trees, fences, paths, roads, and street furniture are from
Kenney's [Car Kit](https://kenney.nl/assets/car-kit) (3.1), [City Kit
(Suburban)](https://kenney.nl/assets/city-kit-suburban) (2.0), [City Kit
(Roads)](https://kenney.nl/assets/city-kit-roads) (2.2), [City Kit
(Commercial)](https://kenney.nl/assets/city-kit-commercial), [City Kit
(Industrial)](https://kenney.nl/assets/city-kit-industrial), [Train
Kit](https://kenney.nl/assets/train-kit), and [Animated Characters
(Retro)](https://kenney.nl/assets/animated-characters-retro), under CC0, in
`vr-project-[car-sim]/assets/kenney/` with their licences, textures, and previews. Each kit is an
asset pack (see Maps). `KitModels` merges each model into one mesh at its pack's size in metres,
facing -Z like the project's cars; parked cars, road users, props, and scenery draw them. Road users are a car of the kit stretched to
their body, or a lorry or van when longer than a car, and keep their look for their whole drive. Pedestrians are the survivors of
Animated Characters (Retro), a man and a woman picked by the road user (`PedestrianModel`), scaled
to the body's height. They stand idle when still and run when moving, the run slowed to the walking
pace, since the kit has no walk; only the survivors' skins are imported, not the zombies'.

The player's car is ["Kiri '86 - Low poly
model"](https://sketchfab.com/3d-models/5c17c582ef9549798f694b660feea42a)
by Daniel Zhabotinsky, licensed [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), in
`vr-project-[car-sim]/assets/sketchfab/kiri86/`: a fictional 80s compact with a modelled cockpit,
its materials made by the game from the model's textures (`PlayerCarModel`). It is scaled to the
car's wheelbase, left-hand drive, and the driver's eyes sit behind its steering wheel. Everything
the car reports is in the car, as in a real one, since the view is VR: the wheels roll and the
front ones steer, the steering wheel turns with the steering, the blinkers, brake lights, reversing
lights, and headlights glow with the car's state, the headlamps cast dipped beams on the road, and
the instrument panel (`InstrumentCluster`), drawn on the model's own gauge face behind the wheel
(cut out of the cabin as the mirrors' glass is), shows the speed on a dial and in figures, the
engine's revolutions and the gear, the indicator arrows blinking, the handbrake, headlights, and
reverse tell-tales, a fuel gauge and a coolant gauge at its ends, and the warning lights; its
needles follow their readings without overshooting. The fuel, the coolant and the warning lights
are for show (`DashState`): with the key on and the engine not running the engine, oil, battery
and ABS lights are lit, going out once it runs (the engine and ABS lights after their self-test),
the stability light flashes while stability or traction control acts, the fuel drains with the
engine's work (about 1% a minute in town) with a low-fuel light under 12%, and the coolant warms
to 90 C over a few minutes and cools when the engine is off. The paint has a
clear coat, and the number plates' letters, the badges, and the tyre walls stand out through normal
maps made from the model's height maps by `tools/kiri86_normals.gd`.

The cabin is the model's one interior mesh, cut by the game when the car is built into the seats,
their leather bolsters, the carpet, the headliner, the door cards, and the dash, by where each
triangle is and which way it faces (`PlayerCarModel.cabin_zone`), and the steering wheel is trimmed
in leather. The model's texture coordinates for its cabin are a trim sheet, so each part gets its
own, laid across it in the car's space along the axis each triangle faces, with one texture
read per map, light enough for a standalone headset. The materials are CC0 sets from
[ambientCG](https://ambientcg.com), in `vr-project-[car-sim]/assets/ambientcg/` with their credits:
[Fabric030](https://ambientcg.com/view?id=Fabric030) for the seats,
[Leather026](https://ambientcg.com/view?id=Leather026) for the bolsters and the wheel,
[Carpet012](https://ambientcg.com/view?id=Carpet012) for the carpet, made grey by
`tools/cabin_textures.gd`, [Fabric034](https://ambientcg.com/view?id=Fabric034) for the
headliner, and [Plastic012A](https://ambientcg.com/view?id=Plastic012A) for the dash and doors;
each is tinted to the car's black cabin.

The car drives on a vehicle model in the spirit of the open-world racing games, real enough to
learn on and forgiving enough to enjoy (`scenarios/vehicle/`). The car is a rigid body of its
spec's mass (`CarSpec`; the Kiri '86 is a rear-wheel drive coupé of 1250 kg) on four suspended
wheels, each cast down to the road for its spring, damper, anti-roll bar and bump stop
(`Suspension`). The engine's torque curve, a six speed gearbox, a limited slip differential, the
brakes, the handbrake and each tyre's rolling resistance turn each wheel (`Powertrain`,
`CarDynamics`). Each tyre's tread is a brush with a relaxation length (`TyreModel.contact`): it
deflects only as its contact patch slides over the road, and rolling at speed its force settles
to a simplified Pacejka magic formula over its combined slip, so braking or pulling hard leaves
less grip for turning, grip grows less than the load on the tyre, and a tyre past its peak
slides. A still patch pushes nothing, and a wheel held by its brake grips as static friction. The
steering (`Steering`) is geometry only: the steering wheel turns the rack, and the rack turns the
front wheels by Ackermann's geometry, the inner one further. It pushes nothing and nothing else
steers, so steered standing still the car stays put, and it turns only as its tyres grip while
it rolls (`WheelContacts` measures how each patch moves along and across its wheel). The weight
moves between the wheels as the car brakes, pulls and turns. The surface under each wheel gives
its friction, from the body it lies on (`BodyType`). The body is free: each spring pushes its own
corner off the road along the road's normal, so it pitches as it brakes and pulls away, rolls in
a turn, follows hills and crests, and can roll over (the attempt's restart is the way back).
The driver's view is fixed to the car, so in a headset the world tilts around the driver as in a
real car. Each tyre grips along the ground under it, so a slope pulls the car down it, and a wheel held still by the brake or the park pawl
holds it there. The model also dips under braking, squats under acceleration and rolls out of a
turn, cockpit, instruments and mirrors included.

The driving aids (`Assists`) come in three presets, set by the project setting `car/assists`:
`exam`, the default and always the one in an exam attempt, with anti-lock brakes, traction
control and stability control; `sport`, with anti-lock brakes and a late traction control; and
`sim`, with anti-lock brakes only. They act through the brakes and the engine, as on a road car,
and never steer. The steering wheel held in VR turns the wheels directly; the keys and sticks turn
it as a hand would, at a hand's pace, the same at any speed, so at speed a small turn is a big
one.

The player's car is built in layers, as a real car is. The plant is the physics: the body, the
suspension, the steering, the contacts, the wheels and tyres (`Suspension`, `Steering`,
`WheelContacts`, `CarDynamics`, `TyreModel`). Its sensors (`CarSensors`) measure it
as hardware does into one record each step (`CarSignals`): each wheel's speed from its own spin,
the output shaft, the crank, a yaw-rate gyro, an accelerometer (it feels 1 g up at rest and nothing
in free fall), the steering angle, the throttle position, and the brake, handbrake and reverse
switches. Its control units decide from those signals alone, a step behind as real ones do
(`CarSystems`): the ABS module (`AbsModule`) estimates the car's speed from the wheels and the
accelerometer, each wheel's slip, the rear's slide and the road's grip, and runs the anti-lock
brakes, traction control and stability control on those estimates; the transmission unit
(`TransmissionUnit`) holds the automatic's gear while the driven wheels flare, as in the air; the
body controller (`BodyController`) lights the brake lamps from the pedal's switch and the reversing
lamps from the reverse switch. Everything the driver reads or feels follows the signals: the
speedometer shows the ABS module's speed from the wheels, so a car falling through the air shows
what its wheels turn at, not its fall, and the lamps, the dash, the controllers' buzz and the
mirror lock read the same record. What is physical follows the plant: the tyres are
heard where they touch the road, each wheel turns at its own spin, and the body leans with its
motion. The exam judges the car from its pose, as an examiner sees it.

The gearbox (`Gearbox`) is an automatic by default, its lever running D, N, R from top to bottom,
moved one notch at a time with `shift_up` and `shift_down`; park is a button of its own (`park`,
or `shift_down` held half a second on a gamepad or the right stick in VR), and leaving it the lever
goes straight to D (up) or R (down), as on a car shifted by wire. The car starts in P, which holds it
with the park pawl, which ratchets while the car rolls and drops in once it is slow. The brake only
brakes, and the throttle drives the way the lever is set, backward in R. Nothing locks the lever
out: R while rolling forward, or D while rolling backward, above a walking pace stalls the engine
with a jolt, and below it the converter takes it up. In D the automatic picks the gear from
the driven wheels' speed, changing up later the harder the throttle is pressed and kicking down
when it is held to the floor, and holds each gear a moment so it never hunts; with the driven
wheels off the road (in the air, upside down) it holds its gear. The accelerator eases toward the
pedal or key as a foot moves it, opening fully in 0.6 s and closing in an eighth of a second, so
tapping a key cruises in top gear (6th from about 80 km/h) and holding it down kicks down to
overtake. With `car/gearbox` set
to `manual`, the same actions change gear through R, N and 1 to 6; a change down past the redline
stalls the engine, and so does coming to a stop in gear with the throttle shut, the clutch let out.
The engine is off, turned over, or running. The key (`ignition`) held turns it over with the
starter, in P or N only (the manual in N), and it catches after a second (`crank_time` in the
`CarSpec`); let go sooner, it does not. A press switches a running engine off, and off, it drives
nothing and its revolutions run down to nothing. A scenario sets how the car starts with a
`CarStart` on its `ScenarioDefinition`: the engine off or running, the lever, and a speed for a
car that starts moving; without one the car starts running, in P. The engine turns on its own inertia (`CarDynamics`): out of gear it revs
freely and settles back to idle; in gear a torque converter (or the clutch, in the manual) slips to
pull away and locks to the driven wheels once they catch up, so the revolutions are the engine's
own, held at the redline by the limiter, and off the ground they climb or fall at the engine's
pace. The tyres squeal when they slide sideways past
their grip and skid when they lock or spin, and the controllers buzz as the anti-lock brakes work.

Road users drive on the same model, as two axles on the lane's grade (`PlanarVehicle`), each with the
spec its size picks (`TrafficSpecs`: a hatchback, a saloon, a van or a lorry). The Intelligent
Driver Model still decides the speed they want; they slow ahead of a bend to what they take it at,
steer to keep their lane, and steer across to the next one to change lanes. Running into a road
user's car trades an impulse between the two by their masses (`Impacts`); hit hard, the road user
crashes and brakes to a halt where the knock leaves it, and the road users behind go round it. All
of the road users' driving stays reproducible and runs on their worker threads; crashes are worked
out on the main thread from the car's state, by geometry, so the same car state gives the same
crash.

The car has an interior mirror and two door mirrors (`CarMirror`), their picture on the model's
own glass: `PlayerCarModel` cuts each housing's face out of the model when the car is built, as it
splits the blinkers, and gives it UVs across the face. Each shows what a mirror there would: a camera at the driver's eye reflected across the
glass looks back through it, cut to the glass's edges, so the picture moves with the head as a real
mirror's does. The door mirrors see a little wider than flat glass, as convex mirrors do. The
reflecting plane is turned within the glass, so the housing round it is cut out of the model too,
onto a visual layer the mirrors leave out, and the picture begins past the glass's far corner:
nothing of the housing comes into its own mirror.

The driver sets the mirrors as in a real car. In VR a grip within 8 cm of a mirror's glass takes
hold of it (`MirrorGrab`), and moving the hand across the glass tilts it, right to see more to the
right, up to see higher. On the keyboard, the gamepad, or the controllers, the mirror switch
(`MirrorAdjust`, the `mirror_adjust` action) picks the interior mirror, then the left, then the
right; the picked mirror's glass lights up a little, and the look controls tilt it instead of
turning the head. Like a car's mirror switch, it is for a car standing still: it lets go once the
car passes 5 km/h, or after 6 s untouched. Each mirror tilts up to 20° either way from where the
car sets it for the seat, and the tilts are kept between sessions in `user://car.cfg`.

To save the frame, the interior mirror is drawn on one frame and the door mirrors
on the next. The project setting `car/mirrors` sets them to `full`, to `low` (half the pixels, one
mirror a frame, for standalone headsets), or `off`. The gaze check judges a mirror look by where the
driver looks: held for a fifth of a second within 12° of the direction from the eye to the mirror, so
a glance with the eyes counts as well as a turn of the head; a car without mirrors is still judged
on the head's turn.

The car sounds from its cabin (`CarSound`), on an audio bus of its own, `Car`. The engine pitches
and swells with the revolutions and the throttle and dips as a gear changes, the indicator ticks as
it blinks, the tyres rumble on the road louder with speed, and a tyre thumps when it meets a kerb. The tyres
have three voices, each driven by its own slip and smoothed so one step's spike passes unheard
(`CarSound.tyre_voices`): a soft scrub that grows as they work toward their grip, there through
any turn or stop; a squeal only when they slide sideways well past their peak slip angle, so a
full-lock turn at 20 km/h stays quiet while one at 30 km/h or a handbrake slide sings; and a
skid, lower and rougher, when the wheels lock or spin, which pulses softly while the anti-lock
brakes work through a hard stop. A gentle stop makes neither. Each surface sounds its own,
crossfading by the share of wheels on it: on the roads the scrub is the roar of a car's tyres on
asphalt; on the loose ground (grass and dirt) the car rolls as on a dirt road, scrubs with the
crunch of tyres on gravel, and any slide, sideways or locked, sprays gravel instead of squealing. The engine at idle,
the road heard from the cabin, and the indicator's relay are CC0 recordings from Freesound, in
`vr-project-[car-sim]/assets/freesound/` with their credits and the downloaded previews they are
cut from by `tools/car_recordings.gd`: [car_idle_loop.wav](https://freesound.org/people/AndrewAlexander/sounds/369053/)
by AndrewAlexander, [Car Driving Interior](https://freesound.org/people/squareal/sounds/237374/)
by squareal, and [Nissan Sentra turning signal](https://freesound.org/people/MPierluissi/sounds/446322/)
by MPierluissi; the tyres on asphalt, [Car rolling on asphalt](https://freesound.org/people/orlandorizo/sounds/591079/)
by orlandorizo; and the loose ground's, a [truck on a dirt road](https://freesound.org/people/kyles/sounds/637192/)
by kyles, a [tyre on gravel](https://freesound.org/people/TRP/sounds/577504/) by TRP, and
[tyres on a gravel shoulder](https://freesound.org/people/UnplugTheFridge/sounds/529225/) by
UnplugTheFridge. The rest is made by the game when the car is built, and so is each recording's
stand-in when its file is missing: the engine's fast loop is a four-cylinder's firing pulses and
their harmonics, crossfaded with the idle as the revolutions rise, the squeal is noise rung
through a few of the tread's resonances, so it rasps like rubber rather than whistling, and the
skid is broad noise with no rings at all.

The Map Kit's roads take the look of City Kit (Roads) (`RoadKit`). The kit's straight road tile is a
cross-section (asphalt, a darker band by the kerb, the kerb, and the pavement) swept along each
`RoadSegment`'s curve, and its crossroads and T tiles are fitted over each `RoadJunction`'s pad.
The tiles are fitted rather than scaled: the asphalt spans the road's lanes, the band and the
pavement keep their widths in metres, and the kerb is as high as the kerb line that is judged. The
kit's own centre line is painted over, since the road's `RoadMarking`s draw the lines that are
judged; a kerb line along a kit road is judged but not drawn, as the road draws the kerb. Each
road and junction pad has one solid pavement body, kerb high and following the curve with no
gaps, which stops the car's tyres; the car drives on the ground beneath the asphalt. A kerb line
drawn by hand, as on the maps built before the kit, is a thin solid wall too. A road given a plain
`surface` material is drawn flat in it instead, and a road without kerbs has no pavement body.

## Scenarios

A scenario is a map plus what is judged on it. The map is the world: roads, markings, lanes,
lights, other road users, signs, props, and where a car may start (see Maps). The scenario is a
scene under `vr-project-[car-sim]/scenarios/scenes/<name>/` that inherits
`scenarios/kit/map_scenario_base.tscn`, instances its map as the `Map` child, and adds the checks,
the zones only checks use, and any steps. The base gives the `Scenario` root and a `Checks` node
already holding `ContactCheck`, `LineCheck`, and `TrafficConflictCheck`. The car starts at the
scenario's `spawn_point`, or else at the map's first `MapSpawn`. Scenarios are laid out with the car
driving towards -Z on the right-hand side of the road, in the lane centred on x = 1.75. Nine of the
ten scenarios are set on the map of the same name in `maps/`; `hill_start` is set on `hill_road`.

Its `ScenarioDefinition`, `definition.tres` beside the scene, gives the id, the title, the menu
category and difficulty, the briefing, the time limit, the scoring policy, and the car scene to
spawn. `scenarios/catalogue.tres`, a `ScenarioCatalogue`, lists every definition in menu order;
menus read it and start a scenario with `ExamRunner.load_definition`.

Checks are nodes placed in the scene, each authoring one rule; when the scenario loads, each becomes
a rule entity judged by the rule's pure functions (`scenarios/rules/`):

| Check | Rule |
|---|---|
| `StopCheck` | A complete stop inside the approach zone before the line zone is entered |
| `RollBackCheck` | Once stopped inside its zone on a hill, rolling back more than `max_roll` (0.5 m) before moving on |
| `SpeedLimitCheck` | The speed limit over a zone, with a grace time and a serious margin |
| `RouteCheck` | Staying in the lane of a `Path3D` centreline, on the road, and not against traffic |
| `LineCheck` | Crossing a solid line, crossing a dashed line without indicating that way, riding on a line, hitting a kerb (a tyre touching or crossing it) |
| `ParkingCheck` | Once settled in a `ParkingBay`: overhanging it, facing the wrong way, too many direction changes, taking too long |
| `TrafficLightCheck` | Crossing the stop line on red, or on amber when the car could have stopped as it changed |
| `CrossingCheck` | Driving onto a pedestrian crossing while someone is on it or about to cross, stopping on it |
| `GazeCheck` | Changing lanes (or moving off) without first looking in the mirror and over the shoulder on that side; optionally the interior mirror too, and the eyes off the road too long |
| `FollowingDistanceCheck` | Staying under a two second time gap behind a road user in the same lane |
| `YieldCheck` | Entering a conflict zone while a road user with priority is in it or due within a safe gap, and waiting too long when the way is clear |
| `JunctionCheck` | Leaving a junction or roundabout by a `JunctionExit` the route does not take, or without indicating that way, read on approach or, at a roundabout, on leaving |
| `ParkingChoiceCheck` | Once settled: parking in a `NoParkingZone` or by a no-parking line, in a reserved bay, or in an occupied one |
| `ContactCheck` | No contact with obstacles or pedestrians |
| `TrafficConflictCheck` | Getting in another road user's way so that it has to brake hard |
| `GoalCheck` | Reaching the goal zone completes the attempt |

Zones are `TriggerZone` boxes, a box collision shape drawn in the editor and judged by geometry.
Road markings are `RoadMarking` paths (solid, dashed, double solid, stop and give way lines, zebra, bay edge,
no-parking line, kerb): the curve draws the paint and is also what `LineCheck` judges, on the
car's wheels rather than its centre. A `ParkingBay` is a parking space, nose-in, reversed, or
either, that may be reserved or occupied; a kerbside space for parallel parking is a bay along the
road. The car counts as parked once it stops with the handbrake on, or stays stopped for a few
seconds. A scenario can run as ordered `ScenarioStep`s, each ended by
its own `GoalCheck`, and a check can be limited to some steps. Each fault a check reports
is a `FaultDef` resource in `scenarios/data/faults/`, naming a severity tier. A `ScoringPolicy`
resource defines the tiers, which of them eliminate at once, and how many faults of each an
attempt may collect and still pass; `default_policy.tres` is a generic policy, and a particular
exam is another policy file.

Other road users play a script by the book until they are forced to react. A `ScriptedAgent`
authors a car or a pedestrian following a `Path3D` at a set speed, starting after a delay or when
the car enters a trigger zone, with an optional pause and loop; the bake turns it into a row of the
road users' columns, and `AgentTable` drives it, including how long it needs to reach any point of
its path.
While its way is clear it moves exactly as scripted, so an attempt plays out the same way each time.
A `TrafficSensor` sweeps the path ahead every tick, and when something is in the way (the player's
car, another road user, a pedestrian, an obstacle) the road user slows or stops by the Intelligent
Driver Model, then returns to its script; road users think on worker threads (see Threads). Each
change is a `reacted` event, and braking harder than its `hard_brake` a `forced_to_brake` event; a
pedestrian waits for a car standing on its way. A road user can also drive to a point: with a
`destination` (usually a `Checkpoint`) and a lane as its path, it starts where it stands on that
lane, takes the shortest way along the lanes to the lane passing nearest the destination
(`LaneRouter`, worked out when the map is baked), reacts to traffic on the way like any other, and
stops there.

Roads are described for road users by `TrafficLane` paths, each along a lane's centre in the
direction of traffic: its speed limit, the lanes it continues onto, its light and stop line, the
lanes it gives way to, its pedestrian crossings, and the lanes beside it. An agent whose path is a
lane keeps to the limit, stops at the line on red (and on amber where it can still stop), waits at
the line until the priority lanes are clear of road users and of the player's car for the lane's
safe gap, waits before a crossing in use, and continues onto the next lane named in its `route`,
or picked from its `route_seed`. Stuck behind something that is not traffic, such as a parked van,
for longer than its `patience`, an agent moves into the lane's left or right neighbour when that
lane is clear around it and the scenario's markings put no solid line or kerb in between; behind a
solid line it waits. In the editor a lane shows its direction and its stop line. A `TrafficSource` feeds a lane with
a flow of reactive cars at headways and routes drawn from its seed, each entering only with room
to stop; the `busy_junction` scenario combines flows, lights, a lane blocked by a van, a crossing,
and a side road. A `TrafficLight` cycles on timers, or holds green until the car approaches and
then changes, so a scenario can place the change at a chosen distance. An `AgentSpawner` fills
parking bays with parked cars chosen from a seed: the same seed gives the same car park.

The car only needs a `VehicleProbe` child: the simulation reads the car's pose through it, with the
indicator and handbrake the car reports, and derives speed, direction, and stops from the pose
alone. `ExamRunner` (`scenarios/scenes/exam_runner.tscn`) spawns a scenario and its car, bakes them
into a world, and runs it; `add_road_user` and `add_obstacle` bake nodes added during an attempt.
The attempt itself is `ExamLogic`, a pure reducer over the rules' results. The `ExamSession` node
turns its events into signals (`briefing_started`, `started`, `step_changed`, `fault_committed`,
`finished`) and the UI's methods (`begin`, `abort`, `restart`, `report_fault`) into its commands;
they are the interface for the UI. `finished` carries a `ScenarioResult` with the outcome and every
fault. Its `to_dict()` gives
the same as plain data: the scenario, the outcome, each fault with its description, and each tier's
count against the policy's limit.

`scenarios/debug/scenario_sandbox.tscn` runs any catalogued scenario, and any map in free drive,
with the `DebugHud`, a flat
overlay showing the briefing, the current step, the time against the limit, faults as they are
committed, how other road users react, the frame and physics times with the traffic pipeline's
share of the main thread, and the result. It runs from the editor. The HUD only listens to the
runner, the session, and the world's events, so it is also a working example of a UI on them; it
hides itself in a headset.

### Maps

[docs/map-guide.md](docs/map-guide.md) walks through building a map with the Map Kit and the Asset
Library, step by step, for readers new to Godot; this section is the reference.

A map is a scene `vr-project-[car-sim]/maps/<name>/<name>.tscn` whose root is a `RoadMap`, with an
id, a title, and a description. `MapCatalogue.scan()` finds every map by its folder, so a map is
added by adding its folder, with no list to edit; a folder without the matching scene is left out
with a warning. A map holds no checks. Any map can be driven on its own in free drive
(`ExamRunner.load_map`), judged only by the checks that need nothing but the map: contact, road
markings, parking places, and conflicts with other road users. Free drive has no goal or time
limit, and ends on a restart or an eliminating fault.

`scenarios/kit/map_base.tscn` is the start of every map: the `RoadMap` root, the shared
`RoadEnvironment` (daylight, sky, and a grass ground sized per map), a `MapSpawn` named `Spawn`, and
empty `Roads`, `Markings`, `Lanes`, `Traffic`, `Signs`, `Props`, and `Zones` nodes to keep the tree
in order. A `MapSpawn` draws a car outline in the editor, facing its direction of travel. A
pedestrian crossing is a `Crossing`: its zone, the pedestrians who use it, and the margin around it.
Lanes list it so their traffic waits while it is in use, and a scenario's `CrossingCheck` points at
it to judge the player there.

The authoring nodes in `scenarios/map/` build the usual parts of a map from a few settings:

| Node | What it builds |
|---|---|
| `RoadSegment` | The road along its curve, in the roads kit's look (see Models), from the lanes each way, the lane width, one way or not, and the kerbs with their pavement width. Its buttons generate the `TrafficLane`s, on the right of their direction of travel, with the speed limit and neighbours set, and the kerbs, centre line, and lane lines as `RoadMarking`s |
| `RoadJunction` | A crossroads or T junction pad for roads of a given width, in the roads kit's look. Its buttons generate a stop or give way line on each controlled arm, and the lanes through the pad from each arm to every other, for one lane each way; who gives way, and lights, are set on those lanes by hand. `arm_end` is where a road leaving by an arm starts |
| `RoadSign` | A sign on a pole: stop, give way, speed limit with its number, no entry, pedestrian crossing, roundabout, no parking, or one way. It is scenery; the rule it shows comes from a lane or a check |
| `Prop` | Not in the palette any more: the Asset Library places models. A parked car, van, cone, barrier, bollard, house, tree, small tree, fence panel, planter, or crate, solid, of the obstacle type (the vehicle type for the cars and vans), so the car collides with it, road users see it, and `ContactCheck` judges touching it. Most show a model of the Kenney kits; `variant` picks among the cars, vans, and houses, and a building's house is stretched to its `building_size` |
| `Scenery` | Not in the palette any more. A footpath, stone path, or driveway from the suburban kit, lying on the ground. It is looks only: nothing collides with it or judges it |
| `Checkpoint` | A point road users drive to. It draws a ring and a flag in the editor and nothing in the game |
| `MapAsset` | Any model of `assets/`, as the Asset Library pane places it: solid, of its category's body type (a box, or the model's own surface for road tiles), or looks only, as its category says, and stretched or scaled as it says. Its settings are saved with the map |

What the buttons generate is ordinary children, saved with the map and editable like any other;
generating again replaces only what the node generated before.

#### Terrain

A map whose land is not flat has a `Terrain` (`scenarios/map/terrain.gd`) and its environment's
`ground` turned off. The land is a height grid of `cell` metres over `size`: a heightmap image first
(white stands `heightmap_height` metres up), then each `TerrainShape` of the map in tree order: a
hill, a valley, a ramp, or a plateau, each with a height, a radius or a size, and a falloff over
which it eases into the land. Under every road and junction the land lies 5 cm below the asphalt,
across the pavements and a 1 m shoulder, and eases back to its own height over `road_blend`. The
land is drawn in chunks and is solid ground. A road climbs and falls with its curve's height and
never banks; a junction is a flat pad at its own height. In the Map Kit, **Add terrain** adds the
node, the palette's Terrain section places the shapes, and **Drape on terrain** sets the selected
roads, lanes, markings, spawns, props, and assets (or the whole map's) on the land in one undoable
step, the roads no steeper than 12%.

The Map Kit editor plugin (`addons/map_kit/`, enabled in `project.godot`) puts all of this in a
dock beside the inspector, in folding sections that stay as they were left:

- **Open map** edits the open map's title and description, and saves or plays it.
- **Maps** lists every map the scan finds. Create a map by name: `maps/<name>/<name>.tscn`, an
  inherited scene of the map base with its id and title, opened at once. Open, play, rename,
  duplicate, or delete the selected map, from the buttons or its right-click menu. Renaming moves
  the folder and scene, sets the id, and rewrites the path in the scenarios using the map;
  a duplicate gets a scene of its own; deleting moves the folder to the trash, and a map a scenario
  uses is never deleted. **Play** saves the map and drives it in free drive in
  `scenarios/debug/map_sandbox.tscn`.
- **Problems** lists the open map's problems as it is edited, warnings before notices, and
  the dock's tab counts the warnings. A missing spawn, a zone without a box, a road with no lanes
  or markings, and a lane whose end meets another's start without a link each have a fix; a lane
  leading nowhere, a spawn off the road, and spawns on top of each other are notices. Selecting one
  selects its node; **Fix all** applies every fix at once.
- **Selection** sets the selected meshes as road (the asphalt material), gives them a solid body on
  the obstacle layer, links the lanes whose ends meet (the selected ones, or all of the map's),
  snaps them to the grid, adds terrain, or drapes them on it (see Terrain). **Next look** steps the selected map assets to the next model of their
  category, and props and scenery to their next look.
- **Road users** turns the selected cars into road users that drive to a checkpoint: select the
  cars (map assets from the Asset Library, props, or road users already) and the checkpoint (or
  leave it out when the map has only one), and press **Drive to checkpoint**. Each becomes a
  `ScriptedAgent` in the car's place, on the lane beside it that runs its way, with its model,
  size, and the lane's speed limit; the overlay draws a dashed line from it to its checkpoint, and
  **Problems** flags one that cannot reach it along the lanes. How it drives is the traffic code's:
  it keeps the rules and reacts to traffic, and there is nothing to script.
- **The palette** holds a road, one-way road, crossroads, T junction, lane, any marking but a bay
  edge (a `ParkingBay` draws its own), traffic light, traffic source, checkpoint, any sign, a spawn,
  a trigger zone, a no-parking zone, a crossing area, a parking bay, and the terrain shapes, with a
  search box; cars,
  houses, trees, and other models are in the Asset Library. Pick a piece and click in the 3D view to
  place it under the map's matching node, on the grid; a road or junction placed near an open road
  end joins it. Shift and click keeps placing, R turns the piece a quarter (Shift and R by 15
  degrees), and Escape or a right click stops. A double click on a piece drops it where the centre
  of the 3D view meets the ground.
- **View** switches the overlay and the Dev HUD, and sets the grid step.

The **Asset Library** pane, a bottom panel beside Output, lists every model in
`vr-project-[car-sim]/assets/`. On the left are the sources: **Favourites**, **Recent** (the last
20 models placed), every pack, and each pack (Car Kit, Suburban, Roads, Commercial, Industrial,
Trains) with its colour; below them are the chosen source's categories (Cars, Houses, Shops and
offices, Shipping containers, and more). On the right are a search box, chips that show only one
body type (obstacle, vehicle, pavement, looks only), a switch between thumbnails and a list, and
the thumbnail size. The search matches every word as part of a model's name, category, or pack;
`pack:`, `cat:`, and `body:` narrow a word to that field, as in `pack:trains body:vehicle tram`.
Thumbnails are rendered by the pane itself (`AssetThumbnails`), each model alone from the same
angle and light, and kept under `.godot/`; a pack's own preview shows until a model's render is
ready. Each is faintly tinted with its pack's colour, and a model whose name another pack also
uses is labelled with its pack's short name, as in "Building a · Commercial". Hovering a model
shows its category, pack, and body type; picking it also shows its size and triangles.

Pick a model and click in the 3D view to place it as a `MapAsset`, or drag it into the view; Shift
and click keeps placing, and a double click or Enter drops it where the centre of the view meets
the ground. While placing, a see-through ghost stands on whatever solid is under the mouse (a road
tile, a pavement, another model), or else on the ground, snapped to the grid across; R turns it a
quarter, Shift and R by 15 degrees, and Shift and E straightens it. Each model keeps the turn it
was last placed with, and Space in the 3D view places the last piece again. Right click a model to
place it at the view's centre, mark it as a favourite (or press F), replace the selected map
assets with it, show it in the FileSystem, or copy its path. **Next look** in the Map Kit dock
steps a map asset to the next model of its category. The pane remembers its source, category,
search, chips, view, size, favourites, recent models, and turns per project, and looks for packs
again when a model or pack file under `assets/` changes, or on **Refresh**.

Assets come in packs: a folder of `.glb` models with a `pack.tres` (an `AssetPack`), and optionally
`previews/<model>.png` thumbnails. The pack file sets the title, a short name for the pane (`tag`; by default the part
of the title in brackets), the credit, the scale to metres, the turn
that faces the models' fronts to -Z, and the categories (`AssetCategory`): which models belong, by
name pattern such as `building-type-*`, their body type (obstacle, vehicle, pavement) or none for
looks only, a size to stretch
them to, a further scale, the solid part of their box (a tree's trunk), and the order they are
listed in. A category of the same name in several packs is listed as one. To add assets, drop a
pack folder anywhere under `assets/`: the pane finds it when the filesystem changes, or on
**Refresh**. A folder of models without a pack file is listed under Other at the models' own size,
solid, and the editor draws thumbnails for models without previews.

The overlay, also on the 3D view's toolbar, draws over the open map: arrows along the lanes, each
lane's end green when it leads on and red when it leads nowhere, a plus on each open road end, the
spawns' numbers, the zones' names, and the map's title with its problem count.

With **Dev HUD when playing** on, **Play** adds the Dev HUD (`scenarios/debug/dev_hud.tscn`) to the
sandbox: the frame rate with a graph of recent frame times, the car's speed, position, heading, and
nearest lane with its limit, the road users near it, the lights, and the session, with tools to try
the map. F3 hides it, F4 flies a free camera, pausing the drive until F4 gives the view back (mouse
to turn, W, A, S, and D to move, Q and E down and up, Shift faster), F5 and F6 slow and speed time
from a quarter to double, F7 pauses, F8 steps one tick while paused, and F9 moves the car to the
next spawn; a check box on its panel draws the world's trigger zones and lanes in 3D.

Every change the dock makes to the open map is one undo step; creating, renaming, duplicating,
and deleting maps, and the save before playing, are not. The work behind it is `MapKitTools`,
which runs without the editor. `maps/sample_town/` is built with the kit alone: a main road
crossed by two side roads that give way, oncoming traffic, signs, parked cars, buildings, and trees. `maps/hill_road/` is the same town on a hill: its main road climbs about 12% from the south onto
a plateau, where the side roads cross it and fall away east and west; the `hill_start` scenario
stops the car halfway up and judges it on rolling back.

To build a map (in more detail in [docs/map-guide.md](docs/map-guide.md)):

1. Create it under **Maps**, and set the environment's ground size to cover the roads.
2. Place a road, shape its curve, and place more roads and junctions on its open ends, which they
   join when placed near one. Generate each road's lanes and markings and each junction's lines
   and lanes with the buttons in the inspector, or draw `TrafficLane` and `RoadMarking` paths by
   hand, and link them with **Connect lanes**. Place lights, sources,
   signs, and the trigger zones that start lights and road users, and models from the Asset
   Library. For a road user, place a car and a checkpoint and press **Drive to checkpoint**; for a
   steady flow, place a traffic source.
3. Move `Spawn` to where the car starts, and add more spawns for other starts.
4. Clear the **Problems**, then **Play**; in the sandbox, M moves from map to map.

### Building a scenario

1. Create the map the scenario is set on, or pick an existing one.
2. Create `scenarios/scenes/<name>/<name>.tscn` as a new inherited scene of
   `scenarios/kit/map_scenario_base.tscn`, instance the map as its `Map` child, and set the root's
   `map` to it. Turn on editable children of `Map` when a check needs to point at a map node, or a
   map node needs changing for this scenario only.
3. Add the checks under `Checks`, each with its zones as children. Faults default to the right
   `FaultDef`, so only a different fault needs setting. The editor flags a check missing a zone,
   and fills each zone with a colour by role: green for a goal, blue for a junction exit, yellow
   for no parking, red where the car must give way or stop.
4. Create `definition.tres` beside the scene, set the scene root's `definition` to it, and add it
   to `scenarios/catalogue.tres`.
5. Add `tests/cases/scenario_<name>_test.gd` with a clean drive and one failing drive per rule.

The scenario tests run headless, one case file per framework area and per scenario under
`tests/cases/`. Scenario cases drive a car through a loaded scenario; framework cases build a world
by hand and step it (`TestCase.sim`), with no scene at all:

```
godot --headless --xr-mode off --fixed-fps 60 --path 'vr-project-[car-sim]' -s res://tests/run_tests.gd
```

`TESTS_FILTER=<name>` runs only the cases whose file name contains it, and `TESTS_VERBOSE=1` prints
each passing test.
