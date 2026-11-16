extends CharacterBody3D
## A stand-in car for building and testing scenarios on the desktop or in a headset. It reads the
## controls through [DriverInput] (keyboard, gamepad), looks through a [DriverView] at the
## driver's seat, and toggle_view switches to a chase camera outside VR. The headless tests turn
## input off and move it directly.

@export var input_enabled := true
@export var acceleration := 6.0
@export var braking := 12.0
@export var max_speed := 25.0
@export var reverse_speed := 5.0
@export var steering_speed := 1.2
## Below this speed, in metres per second, the brake reverses instead.
@export var reverse_threshold := 0.1

var current_speed := 0.0

@onready var probe: VehicleProbe = $VehicleProbe
@onready var driver_view: DriverView = $DriverView
@onready var chase_camera: Camera3D = $ChaseCamera


func _ready() -> void:
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
	var throttle := DriverInput.throttle()
	var brake := DriverInput.brake()
	var handbrake := DriverInput.handbrake()
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
		rotate_y(DriverInput.steer() * steering_speed * delta * signf(current_speed))
	velocity = -global_basis.z * current_speed
	velocity.y = 0.0
	move_and_slide()
