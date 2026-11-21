extends CharacterBody3D
## A stand-in car for building and testing scenarios on the desktop or in a headset. It reads the
## controls through [DriverInput] (keyboard, gamepad), looks through a [DriverView] at the
## driver's seat, and toggle_view switches to a chase camera outside VR. The headless tests turn
## input off and move it directly, or, to drive its physics, keep input on and set
## [member held_controls]. Its body is a model of the car kit, which has no windows or
## inside: it is drawn on render layer 20 alone ([constant BODY_LAYER]), which the driver's view
## leaves out, so only the chase camera shows it.
##
## Its collider is the player's [BodyType]: the body's box rides 0.25 m above the ground, so it
## clears a kerb and may overhang it, and a box for each tyre, at the [VehicleProbe]'s wheels,
## meets the kerb. Kerbs and pavements are solid, so the tyres stop against them.

## The render layer the car's body is drawn on, and the driver's cameras leave out.
const BODY_LAYER := 1 << 19

@export var input_enabled := true
@export var acceleration := 6.0
@export var braking := 12.0
@export var max_speed := 25.0
@export var reverse_speed := 5.0
@export var steering_speed := 1.2
## Below this speed, in metres per second, the brake reverses instead.
@export var reverse_threshold := 0.1

var current_speed := 0.0
## Controls set from code instead of [DriverInput], for tests: [code]{throttle, brake, steer}[/code]
## each from 0 to 1, steer from -1 (full right) to 1 (full left); empty to read the player's
## controls.
var held_controls := {}

@onready var probe: VehicleProbe = $VehicleProbe
@onready var driver_view: DriverView = $DriverView
@onready var chase_camera: Camera3D = $ChaseCamera


func _ready() -> void:
	BodyType.of(&"player").apply(self)
	probe.indicator = VehicleProbe.Indicator.OFF
	probe.handbrake = VehicleProbe.Toggle.OFF
	probe.headlights = VehicleProbe.Toggle.OFF
	driver_view.active = input_enabled


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	var side := DriverInput.indicator_pressed(event)
	if side != VehicleProbe.Indicator.OFF:
		probe.indicator = VehicleProbe.Indicator.OFF if probe.indicator == side else side
	elif event.is_action_pressed(&"toggle_view") and not driver_view.vr:
		driver_view.active = not driver_view.active
		chase_camera.current = not driver_view.active


func _physics_process(delta: float) -> void:
	if not input_enabled:
		return
	var held := not held_controls.is_empty()
	var throttle: float = held_controls.get("throttle", 0.0) if held else DriverInput.throttle()
	var brake: float = held_controls.get("brake", 0.0) if held else DriverInput.brake()
	var handbrake := false if held else DriverInput.handbrake()
	var steer: float = held_controls.get("steer", 0.0) if held else DriverInput.steer()
	probe.handbrake = VehicleProbe.Toggle.ON if handbrake else VehicleProbe.Toggle.OFF

	if handbrake:
		current_speed = move_toward(current_speed, 0.0, braking * 1.5 * delta)
	elif brake > 0.0 and current_speed > reverse_threshold:
		current_speed = move_toward(current_speed, 0.0, braking * brake * delta)
	elif brake > 0.0:
		current_speed = move_toward(current_speed, -reverse_speed * brake, acceleration * delta)
	elif throttle > 0.0:
		var rate := braking if current_speed < 0.0 else acceleration
		current_speed = move_toward(current_speed, max_speed * throttle, rate * delta)
	else:
		current_speed = move_toward(current_speed, 0.0, acceleration * 0.25 * delta)

	if absf(current_speed) > 0.1:
		rotate_y(steer * steering_speed * delta * signf(current_speed))
	velocity = -global_basis.z * current_speed
	velocity.y = 0.0
	move_and_slide()
	# Blocked by something solid, the car keeps only the speed it really made.
	if get_slide_collision_count() > 0:
		var made := get_real_velocity().dot(-global_basis.z)
		current_speed = made if absf(made) < absf(current_speed) else current_speed
