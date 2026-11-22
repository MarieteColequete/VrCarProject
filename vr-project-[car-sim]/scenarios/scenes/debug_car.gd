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
## at each contact patch, on the friction of the surface under it. The body yaws and heaves but
## does not pitch or roll, so the driver's head stays level in a headset; the weight still moves
## between the wheels as it brakes and corners, and the model leans to show it.
##
## Its collider is the player's [BodyType]: the body's box rides 0.25 m above the ground, so it
## clears a kerb and may overhang it, and a box for each tyre, at the [VehicleProbe]'s wheels,
## meets the kerb. Kerbs and pavements are solid, so a slow tyre stops against them.

## Seconds an indicator stays lit, and then dark, as it blinks.
const BLINK := 0.35
## Where the driver's eyes are from the steering wheel's centre, metres: above it and behind.
const EYE_FROM_WHEEL := Vector3(0.0, 0.4, 0.5)
## Where the instruments are from the steering wheel's centre, metres: above it and ahead.
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

## The car's speed along its length, m/s, negative reversing.
var current_speed := 0.0
## The engine, the gearbox, the brakes and the tyres.
var dynamics: CarDynamics
## The gearbox's gear: 1 and up, -1 reversing, 0 in neutral or park. The automatic's lever is
## [code]dynamics.gearbox.selector[/code]; the car starts in park.
var gear: int:
	get:
		return dynamics.gear if dynamics else 0
## The engine's revolutions per minute.
var rpm: float:
	get:
		return dynamics.rpm if dynamics else 850.0
## The throttle held now, 0 to 1.
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
var _braking := false
var _accel := Vector2.ZERO
var _last_velocity := Vector3.ZERO
var _mirror_frame := 0
var _on_kerb := false
var _mirror_quality := "full"
var _blink_clock := 0.0
var _mirror_held := false
var _abs_was := false
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
var _mu_mean := 1.0
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
		instruments.position = model.steering_centre + INSTRUMENTS_FROM_WHEEL
		# In the binnacle, facing the driver, leaning back.
		instruments.rotation = Vector3(deg_to_rad(-20.0), 0.0, 0.0)
		model.cabin.add_child(instruments)
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
	var tilt := mirror_adjust.step(delta, look.stick, current_speed, mouse != Vector2.ZERO)
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


## Whether an indicator blinking for [param clock] seconds is lit: lit first, then dark, each for
## [constant BLINK] seconds.
static func blink_on(clock: float) -> bool:
	return fmod(clock, BLINK * 2.0) < BLINK


## The body as the spec makes it: its mass, its centre of mass between the axles, its turn about
## the vertical, and no pitch or roll.
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
	inertia = Vector3(spec.yaw_inertia, spec.yaw_inertia, spec.yaw_inertia)
	axis_lock_angular_x = true
	axis_lock_angular_z = true
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


## Moves the live parts and the instruments to the car's state.
func _show(delta: float) -> void:
	_blink_clock += delta
	var lit := blink_on(_blink_clock)
	var left := probe.indicator == VehicleProbe.Indicator.LEFT and lit
	var right := probe.indicator == VehicleProbe.Indicator.RIGHT and lit
	var headlights := probe.headlights == VehicleProbe.Toggle.ON
	var reversing := current_speed < -0.1
	if model:
		model.drive(delta, current_speed, _steer, left, right, _braking, reversing, headlights)
		model.lean(delta, _accel.x, _accel.y)
	if sound:
		var blinking := probe.indicator == VehicleProbe.Indicator.LEFT \
			or probe.indicator == VehicleProbe.Indicator.RIGHT
		var work := 0.0
		for i in 4:
			if grounded[i]:
				work = maxf(work, dynamics.usage[i])
		sound.follow(rpm, throttle, dynamics.shifting > 0.0, blinking and lit, work,
			current_speed, dynamics.engine)
	if instruments:
		var parked := probe.handbrake == VehicleProbe.Toggle.ON
		instruments.redline = spec.redline_rpm
		instruments.show_state(delta, absf(current_speed) * 3.6, rpm,
			dynamics.gearbox.letter(), left, right, parked, headlights,
			reversing)


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
		_steer = 0.0
		wheel_angle = 0.0
		_braking = false
		_accel = Vector2.ZERO
		return
	var forward := -global_basis.z
	var up := global_basis.y
	var velocity := linear_velocity
	current_speed = velocity.dot(forward)
	var c := _controls()
	throttle = c.throttle
	var brake: float = c.brake
	probe.handbrake = VehicleProbe.Toggle.ON if c.handbrake > 0.5 else VehicleProbe.Toggle.OFF

	# The brake only brakes; the throttle drives whichever way the gearbox is in.
	_braking = brake > 0.0 and absf(current_speed) > 0.1

	# Hands on the wheel steer it directly; the keys and sticks ease toward their steering, with
	# the aids' lock at speed and their counter-steer.
	var by_hand: bool = not c.held and driver_view.wheel.held()
	var surface := _surface_under()
	if by_hand:
		_steer = driver_view.wheel.steer()
		wheel_angle = _steer * spec.steer_lock
	else:
		var outward: bool = absf(c.steer) > absf(_steer) and c.steer * _steer >= 0.0
		_steer = move_toward(_steer, clampf(c.steer, -1.0, 1.0),
			(STEER_RATE if outward else RETURN_RATE) * delta)
		var rear_slide := (dynamics.angle[CarDynamics.RL] + dynamics.angle[CarDynamics.RR]) * 0.5
		wheel_angle = _steer * Assists.steer_lock(dynamics.aids, _packed, current_speed, surface) \
			+ Assists.counter_steer(dynamics.aids, _packed, rear_slide)
		wheel_angle = clampf(wheel_angle, -spec.steer_lock, spec.steer_lock)

	# The suspension: each wheel cast down to the road.
	var space := get_world_3d().direct_space_state
	var length := spec.travel + spec.wheel_radius
	var loads := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var along := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var across := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var mu := PackedFloat64Array([1.0, 1.0, 1.0, 1.0])
	var contacts := PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
	var squeezed := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var kerb := false
	for i in 4:
		var top := global_transform * (wheel_position(i) + Vector3.UP * CAST_FROM)
		_ray.from = top
		_ray.to = top - up * length
		var hit := space.intersect_ray(_ray)
		grounded[i] = 1 if not hit.is_empty() else 0
		if hit.is_empty():
			squeezed[i] = 0.0
			contacts[i] = top - up * length
			continue
		squeezed[i] = clampf(length - top.distance_to(hit.position), 0.0, spec.travel + 0.05)
		contacts[i] = hit.position
		var other := hit.collider as CollisionObject3D
		if other:
			if other.collision_layer & Layers.PAVEMENT:
				kerb = true
			var material: PhysicsMaterial = other.get(&"physics_material_override")
			if material:
				mu[i] = material.friction
	var support := 0.0
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
		support += spring
	_settled = true
	apply_central_force(up * support)

	# The weight on each wheel: the springs' support, shared as the car's acceleration moves it.
	var share := _weight_shares()
	var weight := spec.mass * CarSpec.G
	var shared := 0.0
	for i in 4:
		shared += share[i] if grounded[i] else 0.0
	for i in 4:
		if grounded[i] and shared > 0.0:
			loads[i] = share[i] / shared * support
	var centre := global_transform * center_of_mass
	for i in 4:
		var heading := forward.rotated(up, wheel_angle) if i < 2 else forward
		var side := up.cross(heading)
		var moving := velocity + angular_velocity.cross(contacts[i] - centre)
		along[i] = moving.dot(heading)
		across[i] = moving.dot(side)

	_mu_mean = (mu[0] + mu[1] + mu[2] + mu[3]) * 0.25
	dynamics.aids = _aids()
	var step := {throttle = c.throttle, brake = brake, handbrake = c.handbrake, steer = wheel_angle,
		shift = c.shift, starter = c.ignition}
	if not str(c.select).is_empty():
		step.select = SELECTOR_LETTERS.find(str(c.select))
	dynamics.step(delta, step, loads, along, across, mu, current_speed, angular_velocity.dot(up))
	for i in 4:
		if not grounded[i]:
			continue
		var heading := forward.rotated(up, wheel_angle) if i < 2 else forward
		var side := up.cross(heading)
		var f := dynamics.force[i]
		apply_force(heading * f.x + side * f.y, contacts[i] - global_position)
	var speed := velocity.length()
	if speed > 0.01:
		apply_central_force(-velocity * 0.5 * CarSpec.AIR * spec.drag_area * speed)
		apply_central_force(-up * 0.5 * CarSpec.AIR * spec.downforce_area * speed * speed)
	if absf(current_speed) > 0.3:
		apply_central_force(-forward * signf(current_speed) * spec.rolling * weight)

	if is_equal_approx(dynamics.shifting, spec.shift_time) or dynamics.shifted:
		driver_view.pulse(0.15, 0.05)
	elif dynamics.shift_refused:
		driver_view.pulse(0.5, 0.15)
	if dynamics.stalled:
		driver_view.pulse(1.0, 0.4)
	elif dynamics.start_refused:
		driver_view.pulse(0.5, 0.15)
	elif dynamics.engine == CarDynamics.EngineState.CRANKING:
		driver_view.pulse(0.15, delta)
	if dynamics.abs_active and not _abs_was:
		driver_view.pulse(0.3, 0.06)
	_abs_was = dynamics.abs_active
	for body in get_colliding_bodies():
		var solid := body as CollisionObject3D
		if solid and solid.collision_layer & Layers.PAVEMENT:
			kerb = true
	if kerb and not _on_kerb:
		if sound:
			sound.knock_kerb()
		driver_view.pulse(0.6, 0.12)
	_on_kerb = kerb

	# The acceleration felt in the car, along it and to its left, smoothed, for the model's lean
	# and the weight's transfer.
	var felt := (velocity - _last_velocity) / delta
	_last_velocity = velocity
	var target := Vector2(felt.dot(forward), felt.dot(up.cross(forward)))
	_accel = _accel.lerp(target, clampf(ACCEL_SMOOTHING * delta, 0.0, 1.0))


## Each wheel's share of the car's weight: its axle's share standing still, moved back as the car
## pulls and forward as it brakes, and outward in a turn.
func _weight_shares() -> PackedFloat64Array:
	var l := spec.wheelbase
	var h := spec.cog_height
	var front := spec.front_share - _accel.x * h / (l * CarSpec.G)
	front = clampf(front, 0.1, 0.9)
	var rear := 1.0 - front
	var side := clampf(_accel.y * h / (spec.track * CarSpec.G), -0.45, 0.45)
	# Turning left (side positive) loads the right wheels.
	return PackedFloat64Array([front * (0.5 - side), front * (0.5 + side), rear * (0.5 - side),
		rear * (0.5 + side)])


## The mean friction of the surface under the wheels in the last step.
func _surface_under() -> float:
	return _mu_mean
