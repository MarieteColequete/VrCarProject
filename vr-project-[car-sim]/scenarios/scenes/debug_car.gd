extends CharacterBody3D
## The player's car, driven in every scenario and in free drive, on the desktop or in a headset. It reads the
## controls through [DriverInput] (keyboard, gamepad), looks through a [DriverView] at the
## driver's seat, and toggle_view switches to a chase camera outside VR. The headless tests turn
## input off and move it directly, or, to drive its physics, keep input on and set
## [member held_controls]. Its body is the [PlayerCarModel], with a cockpit the driver sits in:
## its wheels roll and steer, its steering wheel turns, its lights show the car's state, and the
## [InstrumentCluster] behind the steering wheel shows the speed, the revolutions and the gear, and
## the tell-tales. L (or the
## gamepad's X) switches the headlights. Its gearbox and steering are the [CarDrivetrain]'s: an
## automatic gearbox with the engine's revolutions, and steering along the front wheels with less
## lock at speed.
##
## Its collider is the player's [BodyType]: the body's box rides 0.25 m above the ground, so it
## clears a kerb and may overhang it, and a box for each tyre, at the [VehicleProbe]'s wheels,
## meets the kerb. Kerbs and pavements are solid, so the tyres stop against them.

## Seconds an indicator stays lit, and then dark, as it blinks.
const BLINK := 0.35
## Where the driver's eyes are from the steering wheel's centre, metres: above it and behind.
const EYE_FROM_WHEEL := Vector3(0.0, 0.4, 0.5)
## Where the instruments are from the steering wheel's centre, metres: above it and ahead.
const INSTRUMENTS_FROM_WHEEL := Vector3(0.0, 0.06, -0.15)

@export var input_enabled := true
@export var acceleration := 6.0
@export var braking := 12.0
@export var max_speed := 25.0
@export var reverse_speed := 5.0
## Below this speed, in metres per second, the brake reverses instead.
@export var reverse_threshold := 0.1

var current_speed := 0.0
## The gearbox's gear: 1 to 5, -1 reversing, 0 in neutral; see [CarDrivetrain].
var gear := 0
## The engine's revolutions per minute.
var rpm := CarDrivetrain.IDLE_RPM
## The throttle held now, 0 to 1.
var throttle := 0.0
## The front wheels' turn, radians, left positive.
var wheel_angle := 0.0
## Controls set from code instead of [DriverInput], for tests: [code]{throttle, brake, steer}[/code]
## each from 0 to 1, steer from -1 (full right) to 1 (full left); empty to read the player's
## controls.
var held_controls := {}
## The car as drawn; null when its model does not load.
var model: PlayerCarModel
var instruments: InstrumentCluster

var _steer := 0.0
var _braking := false
var _shifting := 0.0
var _last_speed := 0.0
var _yaw_rate := 0.0
var _blink_clock := 0.0

@onready var probe: VehicleProbe = $VehicleProbe
@onready var driver_view: DriverView = $DriverView
@onready var chase_camera: Camera3D = $ChaseCamera


func _ready() -> void:
	BodyType.of(&"player").apply(self)
	model = PlayerCarModel.make(probe.wheelbase)
	if model:
		add_child(model)
		driver_view.position = model.steering_centre + EYE_FROM_WHEEL
		instruments = InstrumentCluster.new()
		instruments.position = model.steering_centre + INSTRUMENTS_FROM_WHEEL
		# In the binnacle, facing the driver, leaning back.
		instruments.rotation = Vector3(deg_to_rad(-20.0), 0.0, 0.0)
		add_child(instruments)
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
	var side := DriverInput.indicator_pressed(event)
	if side != VehicleProbe.Indicator.OFF:
		_blink_clock = 0.0
		probe.indicator = VehicleProbe.Indicator.OFF if probe.indicator == side else side
	elif event.is_action_pressed(&"toggle_view") and not driver_view.vr:
		driver_view.active = not driver_view.active
		chase_camera.current = not driver_view.active


func _physics_process(delta: float) -> void:
	_drive(delta)
	_show(delta)


## Whether an indicator blinking for [param clock] seconds is lit: lit first, then dark, each for
## [constant BLINK] seconds.
static func blink_on(clock: float) -> bool:
	return fmod(clock, BLINK * 2.0) < BLINK


## Moves the live parts and the instruments to the car's state.
func _show(delta: float) -> void:
	_blink_clock += delta
	var lit := blink_on(_blink_clock)
	var left := probe.indicator == VehicleProbe.Indicator.LEFT and lit
	var right := probe.indicator == VehicleProbe.Indicator.RIGHT and lit
	var headlights := probe.headlights == VehicleProbe.Toggle.ON
	var reversing := current_speed < -0.1
	if model:
		model.drive(delta, current_speed, wheel_angle / CarDrivetrain.LOCK, left, right, _braking,
			reversing, headlights)
		var along := (current_speed - _last_speed) / delta if delta > 0.0 else 0.0
		model.lean(delta, along, current_speed * _yaw_rate)
	_last_speed = current_speed
	if instruments:
		var parked := probe.handbrake == VehicleProbe.Toggle.ON
		instruments.show_state(delta, current_speed * 3.6, rpm,
			CarDrivetrain.gear_letter(gear, current_speed, parked), left, right, parked, headlights,
			reversing)


func _drive(delta: float) -> void:
	if not input_enabled:
		_steer = 0.0
		wheel_angle = 0.0
		_yaw_rate = 0.0
		_braking = false
		return
	var held := not held_controls.is_empty()
	throttle = held_controls.get("throttle", 0.0) if held else DriverInput.throttle()
	var brake: float = held_controls.get("brake", 0.0) if held else DriverInput.brake()
	var handbrake := false if held else DriverInput.handbrake()
	var steer: float = held_controls.get("steer", 0.0) if held else DriverInput.steer()
	probe.handbrake = VehicleProbe.Toggle.ON if handbrake else VehicleProbe.Toggle.OFF
	_braking = brake > 0.0 and current_speed > reverse_threshold

	var shifted := CarDrivetrain.next_gear(gear, current_speed, throttle)
	if shifted != gear:
		# Changing between forward gears drops the drive for a moment.
		_shifting = CarDrivetrain.SHIFT_TIME if gear > 0 and shifted > 0 else 0.0
		gear = shifted
	_shifting = maxf(_shifting - delta, 0.0)
	var pull := 0.0 if _shifting > 0.0 else CarDrivetrain.pull(gear)

	if handbrake:
		current_speed = move_toward(current_speed, 0.0, braking * 1.5 * delta)
	elif brake > 0.0 and current_speed > reverse_threshold:
		current_speed = move_toward(current_speed, 0.0, braking * brake * delta)
	elif brake > 0.0:
		current_speed = move_toward(current_speed, -reverse_speed * brake, acceleration * delta)
	elif throttle > 0.0 and current_speed < 0.0:
		current_speed = move_toward(current_speed, 0.0, braking * delta)
	elif throttle > 0.0:
		current_speed = move_toward(current_speed, max_speed * throttle,
			acceleration * pull * delta)
	else:
		current_speed = move_toward(current_speed, 0.0, acceleration * 0.25 * delta)
	rpm = CarDrivetrain.rpm(current_speed, gear)

	_steer = CarDrivetrain.ease_steer(_steer, steer, delta)
	wheel_angle = _steer * CarDrivetrain.lock_at(current_speed, probe.wheelbase)
	_yaw_rate = CarDrivetrain.yaw_rate(current_speed, wheel_angle, probe.wheelbase)
	rotate_y(_yaw_rate * delta)
	velocity = -global_basis.z * current_speed
	velocity.y = 0.0
	move_and_slide()
	# Blocked by something solid, the car keeps only the speed it really made.
	if get_slide_collision_count() > 0:
		var made := get_real_velocity().dot(-global_basis.z)
		current_speed = made if absf(made) < absf(current_speed) else current_speed
