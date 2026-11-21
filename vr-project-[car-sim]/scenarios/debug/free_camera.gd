class_name FreeCamera
extends Camera3D
## A flying camera for looking round a map while building it: [method open] takes over the view
## from the current camera and pauses the drive; the mouse turns it and WASD moves it, with Q and
## E for down and up and Shift to go faster. [method close] gives the view back to the camera it
## took it from, the driver's, and lets the drive go on as it was. It runs while the tree is
## paused, and moves in real time whatever the engine's time scale.

## Metres per second; Shift multiplies it by [member fast_factor].
@export var speed := 12.0
@export var fast_factor := 4.0
@export var mouse_sensitivity := 0.0025

var yaw := 0.0
var pitch := 0.0

var _previous: Camera3D
var _was_paused := false
var _previous_mouse := Input.MOUSE_MODE_VISIBLE


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Moved every frame, often while the tree is paused: drawn where it is, not interpolated.
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF


## Whether the camera has the view.
func is_open() -> bool:
	return _previous != null or current


## Takes the view over from the viewport's current camera, starting where it looks from, and
## pauses the tree.
func open() -> void:
	if is_open():
		return
	_previous = get_viewport().get_camera_3d()
	if _previous:
		global_transform = _previous.global_transform
		fov = _previous.fov
	var euler := global_basis.get_euler()
	yaw = euler.y
	pitch = euler.x
	_apply_rotation()
	make_current()
	_was_paused = get_tree().paused
	get_tree().paused = true
	_previous_mouse = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Gives the view back to the camera it was taken from, and the tree its pause state.
func close() -> void:
	if not is_open():
		return
	clear_current(false)
	if is_instance_valid(_previous):
		_previous.make_current()
	_previous = null
	get_tree().paused = _was_paused
	Input.mouse_mode = _previous_mouse


func _process(delta: float) -> void:
	if not current:
		return
	var move := Vector3.ZERO
	for pair: Array in [[KEY_D, Vector3.RIGHT], [KEY_A, Vector3.LEFT], [KEY_W, Vector3.FORWARD],
			[KEY_S, Vector3.BACK], [KEY_E, Vector3.UP], [KEY_Q, Vector3.DOWN]]:
		if Input.is_physical_key_pressed(pair[0]):
			move += pair[1]
	if move == Vector3.ZERO:
		return
	var rate := speed * (fast_factor if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0)
	# The process delta follows Engine.time_scale; the camera keeps real time.
	var real := delta / maxf(Engine.time_scale, 0.001)
	global_position += global_basis * move.normalized() * rate * real


func _unhandled_input(event: InputEvent) -> void:
	if not current:
		return
	var motion := event as InputEventMouseMotion
	if motion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= motion.relative.x * mouse_sensitivity
		pitch = clampf(pitch - motion.relative.y * mouse_sensitivity, -1.5, 1.5)
		_apply_rotation()
		get_viewport().set_input_as_handled()


func _apply_rotation() -> void:
	global_basis = Basis.from_euler(Vector3(pitch, yaw, 0.0))


func _exit_tree() -> void:
	close()
