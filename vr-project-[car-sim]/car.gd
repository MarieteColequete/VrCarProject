
extends CharacterBody3D

@export var acceleration: float = 12.0
@export var max_speed: float = 20.0
@export var reverse_speed: float = 8.0
@export var steering_speed: float = 1.5
@export var mouse_sensitivity: float = 0.002

@onready var camera: Camera3D = $DesktopCamera

var current_speed: float = 0.0
var mouse_pitch: float = 0.0
var mouse_yaw: float = 0.0


func _ready():
	camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event):
	if event is InputEventMouseMotion:
		if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			mouse_yaw -= event.relative.x * mouse_sensitivity
			mouse_pitch -= event.relative.y * mouse_sensitivity

			mouse_pitch = clamp(
				mouse_pitch,
				deg_to_rad(-70),
				deg_to_rad(70)
			)

			camera.rotation = Vector3(mouse_pitch, mouse_yaw, 0)

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	if event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta):
	var throttle = 0.0

	if Input.is_key_pressed(KEY_UP) or Input.is_key_pressed(KEY_W):
		throttle = 1.0
	elif Input.is_key_pressed(KEY_DOWN) or Input.is_key_pressed(KEY_S):
		throttle = -1.0
	
	var steering = 0.0
	if Input.is_key_pressed(KEY_LEFT) or Input.is_key_pressed(KEY_A):
		steering = 1.0
	elif Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D):
		steering = -1.0
	

	var target_speed = 0.0

	if throttle > 0:
		target_speed = max_speed
	elif throttle < 0:
		target_speed = -reverse_speed

	current_speed = move_toward(
		current_speed,
		target_speed,
		acceleration * delta
	)
	
	print("4. VELOCIDAD: ", current_speed)

	if abs(current_speed) > 0.1:
		rotate_y(
			steering * steering_speed * delta * sign(current_speed)
		)

	velocity.x = -global_transform.basis.z.x * current_speed
	velocity.z = -global_transform.basis.z.z * current_speed
	velocity.y = 0.0
	
	print("5. VELOCITY: ", velocity)

	move_and_slide()
