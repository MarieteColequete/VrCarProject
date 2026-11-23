extends RigidBody3D
## The player's car, driven in every scenario and in free drive, on the desktop or in a headset. It reads the
## controls through [DriverInput] (keyboard, gamepad), looks through a [DriverView] at the
## driver's seat, and toggle_view switches to a chase camera outside VR. The headless tests turn
## input off and move it directly (the body is then frozen and placed), or, to drive its physics,
## keep input on and set [member held_controls]. Its body is the [PlayerCarModel], with a cockpit
## the driver sits in: its wheels roll and steer, its steering wheel turns, its lights show the
## car's state, and the [InstrumentCluster] behind the steering wheel shows the speed, the
## revolutions and the gear, and the tell-tales. L (or the gamepad's X) switches the headlights.
## The driver sets the mirrors with the mirror switch ([MirrorAdjust]) or, in VR, by hand
## ([MirrorGrab]), and the tilts are kept in [member settings_path].
##
## It drives on the shared vehicle core: a rigid body of the [member spec]'s mass on four
## suspended wheels, each cast down to the road for its spring, damper and anti-roll bar, with
## the engine, the gearbox, the brakes, the aids and the tyres of [CarDynamics] pushing on the road
## at each contact patch, on the friction of the surface under it. The body is free: each spring
## pushes at its own wheel, so it pitches as it brakes and pulls away, rolls in a turn, follows a
## slope, and can roll over. The driver's view is fixed to the car and turns with it, so in a
## headset the world tilts around the driver. The tyres grip along the ground under them, so a slope
## pulls the car down it.
##
## Its collider is the player's [BodyType]: the body's box rides 0.25 m above the ground, so it
## clears a kerb and may overhang it, and a box for each tyre, at the [VehicleProbe]'s wheels,
## meets the kerb. Kerbs and pavements are solid, so a slow tyre stops against them.

## Seconds an indicator stays lit, and then dark, as it blinks.
const BLINK := 0.35
## Where the driver's eyes are from the steering wheel's centre, metres: above it and behind.
const EYE_FROM_WHEEL := Vector3(0.0, 0.4, 0.5)
## Where the instruments are from the steering wheel's centre, metres, above it and ahead, when the
## model has no gauge face to draw them on.
const INSTRUMENTS_FROM_WHEEL := Vector3(0.0, 0.06, -0.15)
## The project setting for the mirrors: [code]full[/code], [code]low[/code] (half the pixels, one
## mirror a frame), or [code]off[/code].
const MIRRORS_SETTING := "car/mirrors"
## The project setting for the gearbox: [code]automatic[/code] or [code]manual[/code].
const GEARBOX_SETTING := "car/gearbox"
## Where each wheel's suspension is cast down from, above the car's base, metres, and how far:
## the wheel's travel and its radius. At rest the car's base sits about on the road.
const CAST_FROM := 0.38
## How much faster the steering moves toward the keys and sticks, and back, in full locks per
## second.
const STEER_RATE := 3.0
const RETURN_RATE := 4.0
## How fast the accelerator opens toward the pedal or key and closes, in full travels per second,
## as a foot moves it: a key held opens it fully in [code]1 / THROTTLE_OPEN[/code] seconds, so a
## tap is a part throttle the automatic cruises on, and only a key held down kicks it down.
const THROTTLE_OPEN := 1.6
const THROTTLE_CLOSE := 8.0
## The automatic's lever positions by letter, in [enum Gearbox.Selector]'s order, for
## [member held_controls]' [code]select[/code].
const SELECTOR_LETTERS := ["P", "R", "N", "D"]
## How quickly the measured acceleration the model leans with settles, per second.
const ACCEL_SMOOTHING := 30.0

@export var input_enabled := true:
	set(value):
		input_enabled = value
		_apply_freeze()
## The car's make-up: engine, gearbox, brakes, tyres, suspension.
@export var spec: CarSpec = preload("res://scenarios/vehicle/specs/kiri86.tres")
## The driving aids' preset ([Assists]); empty takes the project setting.
@export var assist_preset := ""
## How the car starts: its engine, its lever, its speed ([CarStart]); empty, it starts running,
## in park (the manual in neutral), standing still.
@export var start: CarStart

## The body's true speed along its length, m/s, negative reversing: the plant's, for the forces on
## it (drag, rolling resistance) and for tests watching it. Nothing the driver reads or the car's
## electronics use comes from it: they read [member signals].
var current_speed := 0.0
## The engine, the gearbox, the brakes and the tyres: the plant.
var dynamics: CarDynamics
## The car's sensors and control units ([CarSystems]); [member signals] is what they measured and
## decided, the only way the instruments, lights, aids and feedback read the car.
var systems := CarSystems.new()
var signals: CarSignals:
	get:
		return systems.signals
## The gearbox's gear: 1 and up, -1 reversing, 0 in neutral or park. The automatic's lever is
## [code]dynamics.gearbox.selector[/code]; the car starts in park.
var gear: int:
	get:
		return dynamics.gear if dynamics else 0
## The engine's revolutions per minute.
var rpm: float:
	get:
		return dynamics.rpm if dynamics else 850.0
## The accelerator now, 0 to 1, easing toward the pedal or key ([constant THROTTLE_OPEN]).
var throttle := 0.0
## The front wheels' turn, radians, left positive.
var wheel_angle := 0.0
## Controls set from code instead of [DriverInput], for tests: [code]{throttle, brake, steer,
## handbrake}[/code] each from 0 to 1, steer from -1 (full right) to 1 (full left), and
## [code]select[/code] a lever position by letter (P, R, N, D) to put the gearbox in, and
## [code]ignition[/code] whether the key is held; empty to read the player's controls.
var held_controls := {}
## Whether each wheel touches the road, and how far its spring is compressed, metres.
var grounded := PackedByteArray([0, 0, 0, 0])
## Whether each wheel stands on loose ground (the ground [BodyType]: grass and dirt), which the
## sound reads.
var on_loose := PackedByteArray([0, 0, 0, 0])
## The loose ground's surface, by its material's name ([method BodyType.material]).
var _loose_name := BodyType.of(&"ground").title
var compression := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
## The car as drawn; null when its model does not load.
var model: PlayerCarModel
var instruments: InstrumentCluster
## The engine, the indicator's tick, the tyres, and the kerbs, heard in the cabin.
var sound: CarSound
## The interior mirror and the left and right door mirrors, in that order; empty with the
## project setting [code]car/mirrors[/code] off.
var mirrors: Array[CarMirror] = []
## The names the mirrors' tilts are saved by, in the order of [member mirrors].
var mirror_keys: Array[StringName] = []
## The mirror switch, for setting the mirrors with the controls.
var mirror_adjust := MirrorAdjust.new()
## The settings file the driver's mirror tilts are kept in between sessions.
var settings_path := "user://car.cfg"

var _packed: PackedFloat64Array
var _steer := 0.0
var _accel := Vector2.ZERO
var _last_velocity := Vector3.ZERO
var _settled_motion := false
## How fast the grounded tyres' contact patches move over the road, m/s; the plant's.
var _patch_speed := 0.0
var _mirror_frame := 0
var _on_kerb := false
var _mirror_quality := "full"
var _blink_clock := 0.0
var _mirror_held := false
var _abs_was := false
var _shifting_was := false
var _settled := false
var _shift := 0
## The speed, m/s, a [member start] gives the body when it is first let go.
var _launch := 0.0
## Whether the key is read: off during a briefing, whose Enter (or Start) begins the attempt and
## would otherwise switch the engine off too. Turned on, the key counts only once let go.
var key_live := true:
	set(value):
		key_live = value
		_key_wait = value
var _key_wait := false
var _ray := PhysicsRayQueryParameters3D.new()

@onready var probe: VehicleProbe = $VehicleProbe
@onready var driver_view: DriverView = $DriverView
@onready var chase_camera: Camera3D = $ChaseCamera


func _ready() -> void:
	BodyType.of(&"player").apply(self)
	_setup_body()
	probe.mass = spec.mass
	probe.wheelbase = spec.wheelbase
	probe.track = spec.track
	model = PlayerCarModel.make(probe.wheelbase)
	if model:
		add_child(model)
		driver_view.position = model.steering_centre + EYE_FROM_WHEEL
		instruments = InstrumentCluster.new()
		model.cabin.add_child(instruments)
		if model.cluster_face:
			# Drawn on the model's own gauge face behind the wheel.
			instruments.mount(model.cluster_face)
		else:
			instruments.position = model.steering_centre + INSTRUMENTS_FROM_WHEEL
			# In the binnacle, facing the driver, leaning back.
			instruments.rotation = Vector3(deg_to_rad(-20.0), 0.0, 0.0)
		_mount_mirrors()
	sound = CarSound.new()
	add_child(sound)
	probe.indicator = VehicleProbe.Indicator.OFF
	probe.handbrake = VehicleProbe.Toggle.OFF
	probe.headlights = VehicleProbe.Toggle.OFF
	driver_view.active = input_enabled


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if DriverInput.headlights_pressed(event):
		probe.headlights = VehicleProbe.Toggle.OFF if probe.headlights == VehicleProbe.Toggle.ON \
			else VehicleProbe.Toggle.ON
		return
	var shift := DriverInput.shift_pressed(event)
	if shift != 0:
		_shift += shift
		return
	var side := DriverInput.indicator_pressed(event)
	if side != VehicleProbe.Indicator.OFF:
		_blink_clock = 0.0
		probe.indicator = VehicleProbe.Indicator.OFF if probe.indicator == side else side
	elif event.is_action_pressed(MirrorAdjust.ACTION) and not mirrors.is_empty():
		switch_mirror()
	elif event.is_action_pressed(&"toggle_view") and driver_view.spectator:
		driver_view.spectator.next_mode()
	elif event.is_action_pressed(&"toggle_view") and not driver_view.vr:
		driver_view.active = not driver_view.active
		chase_camera.current = not driver_view.active


## Puts the glass on the model's mirrors, set up for the driver's seat, and tells the probe where
## they are, for the gaze checks.
func _mount_mirrors() -> void:
	_mirror_quality = str(ProjectSettings.get_setting(MIRRORS_SETTING, "full"))
	var points := PackedVector3Array()
	var seat := driver_view.position
	for key: StringName in [&"rear", &"left", &"right"]:
		var spot := model.mirror_spot(key, seat)
		if spot.is_empty():
			continue
		var at: Transform3D = spot.transform
		points.append(at.origin)
		if _mirror_quality == "off":
			continue
		var width: int = spot.width / 2 if _mirror_quality == "low" else spot.width
		var mirror := CarMirror.make(String(key).to_pascal_case() + "Mirror", spot.size, width,
			spot.glass)
		mirror.transform = at
		mirror.rest_pivot = at.affine_inverse() * (spot.aim as Transform3D)
		mirror.widen = spot.widen
		mirror.eye = driver_view.eye()
		model.cabin.add_child(mirror)
		mirrors.append(mirror)
		mirror_keys.append(key)
	probe.mirrors = points
	load_mirror_tilts()


## Sets the mirrors as the driver last left them, from [member settings_path].
func load_mirror_tilts() -> void:
	var tilts := CarMirror.load_tilts(settings_path)
	for i in mirrors.size():
		mirrors[i].tilt = tilts.get(mirror_keys[i], Vector2.ZERO)


## Keeps the mirrors as the driver has set them, in [member settings_path].
func save_mirror_tilts() -> void:
	if mirrors.is_empty():
		return
	var tilts := {}
	for i in mirrors.size():
		tilts[mirror_keys[i]] = mirrors[i].tilt
	CarMirror.save_tilts(settings_path, tilts)


## Moves the mirror switch on to the next mirror, or to none, lighting the mirror picked and
## giving it the look controls.
func switch_mirror() -> void:
	mirror_adjust.cycle(mirrors.size())
	_show_picked()


func _show_picked() -> void:
	for i in mirrors.size():
		mirrors[i].selected = i == mirror_adjust.picked
	driver_view.look_locked = mirror_adjust.active()


## A step of the mirror switch: the picked mirror tilts with the look controls; once the switch
## lets go, the mirrors are saved as they are.
func _adjust_mirrors(delta: float) -> void:
	if not mirror_adjust.active():
		return
	var look := driver_view.mirror_look()
	var mouse: Vector2 = look.mouse
	var tilt := mirror_adjust.step(delta, look.stick, signals.vehicle_speed, mouse != Vector2.ZERO)
	if mirror_adjust.active():
		mirrors[mirror_adjust.picked].nudge(tilt + mouse)
	else:
		_show_picked()
		save_mirror_tilts()


## The mirrors in the driver's hands: a held mirror tilts as the hand moves across it, and is
## saved once let go.
func _grab_mirrors() -> void:
	var glasses: Array = mirrors.map(func(m: CarMirror) -> Transform3D: return m.global_transform)
	var tilts := driver_view.grab_mirrors(glasses)
	for i in mini(tilts.size(), mirrors.size()):
		if tilts[i] != Vector2.ZERO:
			mirrors[i].nudge(tilts[i])
	var held := driver_view.mirror_grab.held()
	if _mirror_held and not held:
		save_mirror_tilts()
	_mirror_held = held


## Draws the mirrors, spread over the frames: at full quality the interior mirror one frame and the
## door mirrors the next, at low quality one mirror a frame.
func _process(delta: float) -> void:
	if mirrors.is_empty():
		return
	_adjust_mirrors(delta)
	_mirror_frame += 1
	if _mirror_quality == "low":
		mirrors[_mirror_frame % mirrors.size()].render()
	elif _mirror_frame % 2 == 0:
		mirrors[0].render()
	else:
		for i in range(1, mirrors.size()):
			mirrors[i].render()


func _physics_process(delta: float) -> void:
	if model and input_enabled:
		driver_view.grab_wheel(delta, global_transform * model.steering_frame(),
			model.steering_radius, _steer)
		if not mirrors.is_empty():
			_grab_mirrors()
	_drive(delta)
	_show(delta)


## The tyres' tread speed where they touch the road, m/s: the mean of the grounded wheels' spin at
## their tread, nought with none on the road. Physical, for the sound.
func rolling_tread() -> float:
	var total := 0.0
	var count := 0
	for i in 4:
		if grounded[i]:
			total += absf(dynamics.spin[i]) * spec.wheel_radius
			count += 1
	return total / count if count > 0 else 0.0


## Whether an indicator blinking for [param clock] seconds is lit: lit first, then dark, each for
## [constant BLINK] seconds.
static func blink_on(clock: float) -> bool:
	return fmod(clock, BLINK * 2.0) < BLINK


## The body as the spec makes it: its mass, its centre of mass between the axles, and its turn
## about the vertical, its width (pitch) and its length (roll), all free.
func _setup_body() -> void:
	_packed = spec.packed()
	dynamics = CarDynamics.new(_packed, _aids())
	dynamics.manual = str(ProjectSettings.get_setting(GEARBOX_SETTING, "automatic")) == "manual"
	if dynamics.manual:
		# A manual car is left in neutral with its handbrake; nothing holds it but the brakes.
		dynamics.gearbox.select(Gearbox.Selector.NEUTRAL)
	if start:
		dynamics.place(start.running(), start.selector(), start.speed)
		_launch = start.speed
	mass = spec.mass
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3(0.0, spec.cog_height, spec.wheelbase * (0.5 - spec.front_share))
	inertia = Vector3(spec.pitch_inertia, spec.yaw_inertia, spec.roll_inertia)
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.0
	angular_damp = 0.0
	can_sleep = false
	contact_monitor = true
	max_contacts_reported = 8
	_ray.collision_mask = Layers.WORLD | Layers.PAVEMENT
	_ray.exclude = [get_rid()]
	_apply_freeze()


func _aids() -> PackedFloat64Array:
	return Assists.from_settings() if assist_preset.is_empty() else Assists.preset(assist_preset)


## Frozen and placed by hand while input is off, as the tests drive it; a body again with input.
func _apply_freeze() -> void:
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = not input_enabled
	if not input_enabled:
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		_settled = false
	elif _launch > 0.0 and is_inside_tree():
		# A car that starts moving gets its speed the first time it is let go.
		linear_velocity = -global_basis.z * _launch
		_launch = 0.0


## Gives the body the impulse, N·s, the road users it ran into gave it ([Impacts]).
func knock(impulse: Vector3) -> void:
	if input_enabled and impulse != Vector3.ZERO:
		apply_central_impulse(impulse)


## Where wheel [param i] (front left, front right, rear left, rear right) is under the car, in its
## own space, at the probe's footprint.
func wheel_position(i: int) -> Vector3:
	var x := probe.track * 0.5 * (-1.0 if i % 2 == 0 else 1.0)
	var z := -probe.wheelbase * 0.5 if i < 2 else probe.wheelbase * 0.5
	return Vector3(x, 0.0, z)


## Moves the live parts and the instruments to the car's state. What the driver reads (the
## instruments, the lamps) comes from the car's signals ([member signals]); what is physical (the
## wheels turning, the body leaning, the tyres heard) from the plant.
func _show(delta: float) -> void:
	_blink_clock += delta
	var lit := blink_on(_blink_clock)
	var left := probe.indicator == VehicleProbe.Indicator.LEFT and lit
	var right := probe.indicator == VehicleProbe.Indicator.RIGHT and lit
	var headlights := probe.headlights == VehicleProbe.Toggle.ON
	if model:
		model.drive(delta, dynamics.spin, _steer, left, right, signals.brake_light,
			signals.reverse_light, headlights)
		model.lean(delta, _accel.x, _accel.y)
	if sound:
		var blinking := probe.indicator == VehicleProbe.Indicator.LEFT \
			or probe.indicator == VehicleProbe.Indicator.RIGHT
		# The tyres are heard where they meet the road: they slip and slide as fast as their contact
		# patches move over it, and roll as fast as their tread turns on it, so a car in the air is
		# silent and a locked wheel skids without rolling.
		var tread := rolling_tread()
		var tyres := CarSound.tyre_voices(_packed, dynamics.ratio, dynamics.angle, dynamics.force,
			grounded, _patch_speed, on_loose)
		sound.follow(signals.rpm, signals.throttle_position, signals.shifting, blinking and lit,
			tyres, tread, signals.engine_state, signals.abs_active, delta)
	if instruments:
		var parked := probe.handbrake == VehicleProbe.Toggle.ON
		instruments.redline = spec.redline_rpm
		instruments.dash.step(delta, signals.engine_state, signals.rpm, signals.throttle_position,
			signals.stalled, signals.esc_active or signals.tcs_active)
		# The speedometer reads the ABS module's speed, from the wheels: it shows what the wheels
		# say, not how fast the body moves through the air.
		instruments.show_state(delta, absf(signals.vehicle_speed) * 3.6, signals.rpm,
			signals.gear_letter, left, right, parked, headlights, signals.reverse_light)


## The controls this step: the tests' held ones, or the player's.
func _controls() -> Dictionary:
	var shift := _shift
	_shift = 0
	if not held_controls.is_empty():
		return {throttle = float(held_controls.get("throttle", 0.0)),
			brake = float(held_controls.get("brake", 0.0)),
			handbrake = float(held_controls.get("handbrake", 0.0)),
			steer = float(held_controls.get("steer", 0.0)), shift = shift, held = true,
			select = held_controls.get("select", ""),
			ignition = bool(held_controls.get("ignition", false))}
	return {throttle = DriverInput.throttle(), brake = DriverInput.brake(),
		handbrake = 1.0 if DriverInput.handbrake() else 0.0, steer = DriverInput.steer(),
		shift = shift, held = false, select = "", ignition = _key()}


## The key as the car reads it: never while [member key_live] is off, and once on, only after it
## has been let go.
func _key() -> bool:
	var held := DriverInput.ignition()
	if not held:
		_key_wait = false
	return held and key_live and not _key_wait


func _drive(delta: float) -> void:
	if not input_enabled or delta <= 0.0:
		throttle = 0.0
		_steer = 0.0
		wheel_angle = 0.0
		_accel = Vector2.ZERO
		return
	var forward := -global_basis.z
	var up := global_basis.y
	var velocity := linear_velocity
	current_speed = velocity.dot(forward)
	var c := _controls()
	throttle = move_toward(throttle, clampf(c.throttle, 0.0, 1.0),
		(THROTTLE_OPEN if c.throttle > throttle else THROTTLE_CLOSE) * delta)
	var brake: float = c.brake
	probe.handbrake = VehicleProbe.Toggle.ON if c.handbrake > 0.5 else VehicleProbe.Toggle.OFF

	# The brake only brakes; the throttle drives whichever way the gearbox is in.

	# Hands on the wheel steer it directly; the keys and sticks ease toward their steering, with
	# the aids' lock at speed and their counter-steer.
	var by_hand: bool = not c.held and driver_view.wheel.held()
	if by_hand:
		_steer = driver_view.wheel.steer()
		wheel_angle = _steer * spec.steer_lock
	else:
		var outward: bool = absf(c.steer) > absf(_steer) and c.steer * _steer >= 0.0
		_steer = move_toward(_steer, clampf(c.steer, -1.0, 1.0),
			(STEER_RATE if outward else RETURN_RATE) * delta)
		# Steering help reads the car's sensors: its speed from the wheels, and the rear's slide
		# from the gyro and the accelerometer. It assumes dry asphalt: it cannot see the road.
		wheel_angle = _steer * Assists.steer_lock(dynamics.aids, _packed, signals.vehicle_speed,
			1.0) + Assists.counter_steer(dynamics.aids, _packed, signals.rear_slip)
		wheel_angle = clampf(wheel_angle, -spec.steer_lock, spec.steer_lock)

	# The suspension: each wheel cast down to the road.
	var space := get_world_3d().direct_space_state
	var length := spec.travel + spec.wheel_radius
	var loads := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var along := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var across := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var mu := PackedFloat64Array([1.0, 1.0, 1.0, 1.0])
	var contacts := PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
	var normals := PackedVector3Array([up, up, up, up])
	var squeezed := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var kerb := false
	for i in 4:
		var top := global_transform * (wheel_position(i) + Vector3.UP * CAST_FROM)
		_ray.from = top
		_ray.to = top - up * length
		var hit := space.intersect_ray(_ray)
		grounded[i] = 1 if not hit.is_empty() else 0
		on_loose[i] = 0
		if hit.is_empty():
			squeezed[i] = 0.0
			contacts[i] = top - up * length
			continue
		squeezed[i] = clampf(length - top.distance_to(hit.position), 0.0, spec.travel + 0.05)
		contacts[i] = hit.position
		normals[i] = hit.normal
		var other := hit.collider as CollisionObject3D
		if other:
			if other.collision_layer & Layers.PAVEMENT:
				kerb = true
			var material: PhysicsMaterial = other.get(&"physics_material_override")
			if material:
				mu[i] = material.friction
				on_loose[i] = 1 if material.resource_name == _loose_name else 0
	for i in 4:
		if not grounded[i]:
			compression[i] = 0.0
			continue
		var partner := i ^ 1
		var rate := (squeezed[i] - compression[i]) / delta if _settled else 0.0
		var spring := CarDynamics.corner_load(_packed, squeezed[i], rate, squeezed[partner])
		# Hitting the end of its travel, a bump stop takes the rest.
		if squeezed[i] > spec.travel:
			spring += (squeezed[i] - spec.travel) * spec.spring_rate * 20.0
		compression[i] = squeezed[i]
		# Each spring pushes its own corner up, so the body pitches and rolls on them, and the
		# weight on each wheel is what its spring carries.
		apply_force(up * spring, contacts[i] - global_position)
		loads[i] = spring
	_settled = true
	var weight := spec.mass * CarSpec.G

	# Each tyre works on the ground's plane under it: its heading and side, along the slope.
	var headings := PackedVector3Array([forward, forward, forward, forward])
	var sides := PackedVector3Array([forward, forward, forward, forward])
	for i in 4:
		var n := normals[i]
		var aim := forward.rotated(up, wheel_angle) if i < 2 else forward
		var flat := aim - n * aim.dot(n)
		headings[i] = flat.normalized() if flat.length_squared() > 0.0001 else aim
		sides[i] = n.cross(headings[i])
	var centre := global_transform * center_of_mass
	for i in 4:
		var heading := headings[i]
		var side := sides[i]
		var moving := velocity + angular_velocity.cross(contacts[i] - centre)
		along[i] = moving.dot(heading)
		across[i] = moving.dot(side)
	var patches := 0.0
	for i in 4:
		if grounded[i]:
			patches += Vector2(along[i], across[i]).length() / grounded.count(1)
	_patch_speed = patches

	# The car's electronics: its sensors measure the plant, its control units decide, and the plant
	# then applies what they asked.
	dynamics.aids = _aids()
	var felt := (velocity - _last_velocity) / delta if _settled_motion else Vector3.ZERO
	_last_velocity = velocity
	_settled_motion = true
	var specific := felt - get_gravity()
	var left := up.cross(forward)
	systems.sense(dynamics, {yaw_rate = angular_velocity.dot(up),
		specific_force = Vector3(specific.dot(forward), specific.dot(left), specific.dot(up))},
		{steer_angle = wheel_angle, throttle = throttle, brake = brake, handbrake = c.handbrake})
	systems.decide(_packed, dynamics.aids, delta)
	var step := {throttle = throttle, brake = brake, handbrake = c.handbrake, steer = wheel_angle,
		shift = c.shift, starter = c.ignition}
	if not str(c.select).is_empty():
		step.select = SELECTOR_LETTERS.find(str(c.select))
	dynamics.step(delta, step, loads, along, across, mu, systems.signals)
	for i in 4:
		if not grounded[i]:
			continue
		var f := dynamics.force[i]
		apply_force(headings[i] * f.x + sides[i] * f.y, contacts[i] - global_position)
	var speed := velocity.length()
	if speed > 0.01:
		apply_central_force(-velocity * 0.5 * CarSpec.AIR * spec.drag_area * speed)
		apply_central_force(-up * 0.5 * CarSpec.AIR * spec.downforce_area * speed * speed)
	if absf(current_speed) > 0.3 and grounded.count(1) > 0:
		apply_central_force(-forward * signf(current_speed) * spec.rolling * weight)

	# What the driver feels through the controllers comes from the car's signals: a change
	# beginning or going through, a refusal, a stall, the starter, ABS working. The kerb below is
	# physical, a bump through the body.
	if (signals.shifting and not _shifting_was) or signals.shifted:
		driver_view.pulse(0.15, 0.05)
	elif signals.shift_refused:
		driver_view.pulse(0.5, 0.15)
	_shifting_was = signals.shifting
	if signals.stalled:
		driver_view.pulse(1.0, 0.4)
	elif signals.start_refused:
		driver_view.pulse(0.5, 0.15)
	elif signals.engine_state == CarDynamics.EngineState.CRANKING:
		driver_view.pulse(0.15, delta)
	if signals.abs_active and not _abs_was:
		driver_view.pulse(0.3, 0.06)
	_abs_was = signals.abs_active
	for body in get_colliding_bodies():
		var solid := body as CollisionObject3D
		if solid and solid.collision_layer & Layers.PAVEMENT:
			kerb = true
	if kerb and not _on_kerb:
		if sound:
			sound.knock_kerb()
		driver_view.pulse(0.6, 0.12)
	_on_kerb = kerb

	# The body's acceleration along it and to its left, smoothed, for the model's lean: the plant's
	# own motion, a physical effect, not a measurement (on a slope at rest it leans nothing).
	_accel = _accel.lerp(Vector2(felt.dot(forward), felt.dot(left)),
		clampf(ACCEL_SMOOTHING * delta, 0.0, 1.0))

