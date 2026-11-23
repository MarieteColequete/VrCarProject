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

## The body's true speed along its length, m/s, negative reversing: the plant's, for tests watching
## it. Nothing the driver reads or the car's
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
## Whether each wheel touches the road.
var grounded := PackedByteArray([0, 0, 0, 0])
## Whether each wheel stands on loose ground (the ground [BodyType]: grass and dirt), which the
## sound reads.
var on_loose := PackedByteArray([0, 0, 0, 0])
## The loose ground's surface, by its material's name ([method BodyType.material]).
var _loose_name := BodyType.of(&"ground").title
## The plant's parts: the steering ([Steering]), the corners' springs ([Suspension]), and where the
## tyres meet the road ([WheelContacts]).
var steering := Steering.new()
var suspension := Suspension.new()
var wheel_contacts := WheelContacts.new()
## The car as drawn; null when its model does not load.
var model: PlayerCarModel
var instruments: InstrumentCluster
## The engine, the indicator's tick, the tyres, and the kerbs, heard in the cabin.
var sound: CarSound
## The car's mirrors ([CarMirrors]): the glass, the switch, the hands, and the tilts kept.
var car_mirrors := CarMirrors.new()
## The interior mirror and the left and right door mirrors, in that order; empty with the
## project setting [code]car/mirrors[/code] off.
var mirrors: Array[CarMirror]:
	get:
		return car_mirrors.mirrors
## The settings file the driver's mirror tilts are kept in between sessions.
var settings_path := "user://car.cfg"

var _packed: PackedFloat64Array
var _steer := 0.0
var _accel := Vector2.ZERO
var _last_velocity := Vector3.ZERO
var _settled_motion := false
## How fast the grounded tyres' contact patches move over the road, m/s; the plant's.
var _patch_speed := 0.0
var _blink_clock := 0.0
## What the driver feels through the controllers.
var feedback := CarFeedback.new()
## Each wheel's cast this step ([method _cast_wheels]): where it touches, the road's normal and
## friction there, and how far it is pushed into its travel.
var _contacts := PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
var _normals := PackedVector3Array([Vector3.UP, Vector3.UP, Vector3.UP, Vector3.UP])
var _mu := PackedFloat64Array([1.0, 1.0, 1.0, 1.0])
var _squeezed := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var _shift := 0
## The park button pressed since the last step, and the gamepad's shift_down ([HoldTap]).
var _park := false
var _pad_down := HoldTap.new()
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
	car_mirrors.name = "Mirrors"
	add_child(car_mirrors)
	probe.mass = spec.mass
	probe.wheelbase = spec.wheelbase
	probe.track = spec.track
	model = PlayerCarModel.make(probe.wheelbase)
	if model:
		add_child(model)
		driver_view.position = model.steering_centre + EYE_FROM_WHEEL
		instruments = InstrumentCluster.new()
		instruments.redline = spec.redline_rpm
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
	if DriverInput.park_pressed(event):
		_park = true
		return
	if DriverInput.is_pad_shift_down(event):
		# The gamepad's shift_down: held, it parks; let go sooner, it moves the lever down.
		if event.is_pressed():
			_pad_down.press()
		elif _pad_down.release():
			_shift -= 1
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
	car_mirrors.settings_path = settings_path
	probe.mirrors = car_mirrors.mount(model, driver_view,
		str(ProjectSettings.get_setting(MIRRORS_SETTING, "full")))


## Moves the mirror switch on to the next mirror, or to none ([method CarMirrors.switch]).
func switch_mirror() -> void:
	car_mirrors.switch()


## Keeps the mirrors as the driver has set them ([method CarMirrors.save_tilts]).
func save_mirror_tilts() -> void:
	car_mirrors.save_tilts()


func _process(delta: float) -> void:
	car_mirrors.step_switch(delta, signals.vehicle_speed)
	car_mirrors.draw()


func _physics_process(delta: float) -> void:
	if _pad_down.advance(delta):
		_park = true
	if model and input_enabled:
		driver_view.grab_wheel(delta, global_transform * model.steering_frame(),
			model.steering_radius, _steer)
		car_mirrors.step_hands()
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
		suspension.reset()
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
		model.drive(delta, dynamics.spin, steering, left, right, signals.brake_light,
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
	var park := _park
	_park = false
	if not held_controls.is_empty():
		return {throttle = float(held_controls.get("throttle", 0.0)), park = bool(
			held_controls.get("park", false)) or park,
			brake = float(held_controls.get("brake", 0.0)),
			handbrake = float(held_controls.get("handbrake", 0.0)),
			steer = float(held_controls.get("steer", 0.0)), shift = shift, held = true,
			select = held_controls.get("select", ""),
			ignition = bool(held_controls.get("ignition", false))}
	return {throttle = DriverInput.throttle(), brake = DriverInput.brake(),
		handbrake = 1.0 if DriverInput.handbrake() else 0.0, steer = DriverInput.steer(),
		shift = shift, held = false, select = "", ignition = _key(), park = park}


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
		steering.steer(_packed, 0.0)
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

	_turn_wheel(c, delta)
	var kerb := _cast_wheels(up)
	var contacts := _contacts
	var normals := _normals
	var mu := _mu
	# Each spring pushes its own corner up off the road, along the road's normal: the body
	# pitches and rolls on them, and the weight on each wheel is what its spring carries.
	var loads := suspension.loads(_packed, _squeezed, grounded, delta)
	for i in 4:
		if grounded[i]:
			apply_force(normals[i] * loads[i], contacts[i] - global_position)

	# Each tyre works on the ground's plane under it, at its wheel's road angle.
	var centre := global_transform * center_of_mass
	wheel_contacts.measure(forward, up, velocity, angular_velocity, centre, steering.angles,
		contacts, normals)
	var along := wheel_contacts.along
	var across := wheel_contacts.across
	var patches := 0.0
	var standing := grounded.count(1)
	for i in 4:
		if grounded[i]:
			patches += Vector2(along[i], across[i]).length() / standing
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
	var step := {throttle = throttle, brake = brake, handbrake = c.handbrake,
		angles = steering.angles, shift = c.shift, starter = c.ignition, park = c.park}
	if not str(c.select).is_empty():
		step.select = SELECTOR_LETTERS.find(str(c.select))
	dynamics.step(delta, step, loads, along, across, mu, systems.signals)
	for i in 4:
		if not grounded[i]:
			continue
		var f := dynamics.force[i]
		apply_force(wheel_contacts.headings[i] * f.x + wheel_contacts.sides[i] * f.y,
			contacts[i] - global_position)
	var speed := velocity.length()
	if speed > 0.01:
		apply_central_force(-velocity * 0.5 * CarSpec.AIR * spec.drag_area * speed)
		apply_central_force(-up * 0.5 * CarSpec.AIR * spec.downforce_area * speed * speed)

	# What the driver feels through the controllers ([CarFeedback]): from the car's signals, and
	# the kerb's bump through the body, which is physical.
	for body in get_colliding_bodies():
		var solid := body as CollisionObject3D
		if solid and solid.collision_layer & Layers.PAVEMENT:
			kerb = true
	for pulse in feedback.step(signals, kerb, delta):
		driver_view.pulse(pulse.x, pulse.y)
	if feedback.kerb_hit and sound:
		sound.knock_kerb()

	# The body's acceleration along it and to its left, smoothed, for the model's lean: the plant's
	# own motion, a physical effect, not a measurement (on a slope at rest it leans nothing).
	_accel = _accel.lerp(Vector2(felt.dot(forward), felt.dot(left)),
		clampf(ACCEL_SMOOTHING * delta, 0.0, 1.0))


## The driver turns the steering wheel: hands on it turn it directly; the keys and sticks turn it
## as a hand would, at a hand's pace toward where they point. The steering only turns the front
## wheels; nothing else steers.
func _turn_wheel(c: Dictionary, delta: float) -> void:
	if not c.held and driver_view.wheel.held():
		_steer = driver_view.wheel.steer()
	else:
		var outward: bool = absf(c.steer) > absf(_steer) and c.steer * _steer >= 0.0
		_steer = move_toward(_steer, clampf(c.steer, -1.0, 1.0),
			(STEER_RATE if outward else RETURN_RATE) * delta)
	steering.steer(_packed, _steer)
	wheel_angle = steering.rack


## Casts each wheel down to the road along the body's [param up]: where it touches, the road's
## normal and friction there, how far the wheel is pushed into its travel, and whether it is on
## loose ground ([member _contacts], [member _normals], [member _mu], [member _squeezed],
## [member grounded], [member on_loose]). Returns whether a wheel stands on a kerb.
func _cast_wheels(up: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var length := spec.travel + spec.wheel_radius
	var kerb := false
	for i in 4:
		var top := global_transform * (wheel_position(i) + Vector3.UP * CAST_FROM)
		_ray.from = top
		_ray.to = top - up * length
		var hit := space.intersect_ray(_ray)
		grounded[i] = 1 if not hit.is_empty() else 0
		on_loose[i] = 0
		_mu[i] = 1.0
		_normals[i] = up
		if hit.is_empty():
			_squeezed[i] = 0.0
			_contacts[i] = top - up * length
			continue
		_squeezed[i] = clampf(length - top.distance_to(hit.position), 0.0, spec.travel + 0.05)
		_contacts[i] = hit.position
		_normals[i] = hit.normal
		var other := hit.collider as CollisionObject3D
		if other:
			if other.collision_layer & Layers.PAVEMENT:
				kerb = true
			var material: PhysicsMaterial = other.get(&"physics_material_override")
			if material:
				_mu[i] = material.friction
				on_loose[i] = 1 if material.resource_name == _loose_name else 0
	return kerb
