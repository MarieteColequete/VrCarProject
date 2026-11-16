extends CharacterBody3D
## A stand-in car for building and testing scenarios on the desktop: arrow keys or WASD, Space
## to brake, Q and E for the indicators, a chase camera. The headless tests turn input off and
## move it directly.

@export var input_enabled := true
@export var acceleration := 6.0
@export var braking := 12.0
@export var max_speed := 25.0
@export var reverse_speed := 5.0
@export var steering_speed := 1.2

var current_speed := 0.0

@onready var probe: VehicleProbe = $VehicleProbe


func _ready() -> void:
	probe.indicator = VehicleProbe.Indicator.OFF
	$ChaseCamera.current = input_enabled


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_Q:
			probe.indicator = _toggle(VehicleProbe.Indicator.LEFT)
		KEY_E:
			probe.indicator = _toggle(VehicleProbe.Indicator.RIGHT)


func _toggle(side: VehicleProbe.Indicator) -> VehicleProbe.Indicator:
	return VehicleProbe.Indicator.OFF if probe.indicator == side else side


func _physics_process(delta: float) -> void:
	if not input_enabled:
		return
	var throttle := Input.get_axis(&"ui_down", &"ui_up")
	if Input.is_key_pressed(KEY_W):
		throttle = 1.0
	elif Input.is_key_pressed(KEY_S):
		throttle = -1.0
	var steering := Input.get_axis(&"ui_right", &"ui_left")
	if Input.is_key_pressed(KEY_A):
		steering = 1.0
	elif Input.is_key_pressed(KEY_D):
		steering = -1.0

	if Input.is_key_pressed(KEY_SPACE):
		current_speed = move_toward(current_speed, 0.0, braking * delta)
	elif throttle > 0.0:
		current_speed = move_toward(current_speed, max_speed, acceleration * delta)
	elif throttle < 0.0:
		var rate := braking if current_speed > 0.0 else acceleration
		current_speed = move_toward(current_speed, -reverse_speed, rate * delta)
	else:
		current_speed = move_toward(current_speed, 0.0, acceleration * 0.25 * delta)

	if absf(current_speed) > 0.1:
		rotate_y(steering * steering_speed * delta * signf(current_speed))
	velocity = -global_basis.z * current_speed
	velocity.y = 0.0
	move_and_slide()
