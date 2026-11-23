class_name ChaseCamera
extends Camera3D
## The flat chase view behind the car (toggle_view, outside VR): it orbits the car with the same
## look controls as the driver's view, the mouse (while captured) and the right stick, zooms with
## chase_zoom_in and chase_zoom_out (the mouse wheel), and look_reset puts it back behind the car.
## It rides with the car, so it turns as the car turns.

const ZOOM_IN := &"chase_zoom_in"
const ZOOM_OUT := &"chase_zoom_out"

@export var mouse_sensitivity := 0.0025
## Radians a second at the stick's full tilt.
@export var stick_speed := 2.5
## Where it looks, metres above the car's base, and how far it stands from there.
@export var pivot_height := 1.0
@export var distance := 7.8
## How far it may come in and go out, metres, and each wheel notch's step.
@export var nearest := 3.5
@export var farthest := 16.0
@export var zoom_step := 0.6
## How far below and above the car it may look down from, degrees.
@export var min_pitch_degrees := -5.0
@export var max_pitch_degrees := 70.0

## Its turn round the car, radians, 0 behind it, and how far it looks down, radians.
var yaw := 0.0
var pitch := deg_to_rad(15.0)

var _rest_distance := 0.0


func _ready() -> void:
	_rest_distance = distance
	_apply()


## Puts it back behind the car at its own distance.
func reset_view() -> void:
	yaw = 0.0
	pitch = deg_to_rad(15.0)
	distance = _rest_distance
	_apply()


## Orbits it by [param delta_yaw] round the car and [param delta_pitch] down, radians.
func orbit(delta_yaw: float, delta_pitch: float) -> void:
	yaw = wrapf(yaw + delta_yaw, -PI, PI)
	pitch = clampf(pitch + delta_pitch, deg_to_rad(min_pitch_degrees),
		deg_to_rad(max_pitch_degrees))
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if not current:
		return
	if event.is_action_pressed(DriverView.LOOK_RESET):
		reset_view()
	elif event.is_action_pressed(DriverView.RELEASE_MOUSE):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event.is_action_pressed(ZOOM_IN) or event.is_action_pressed(ZOOM_OUT):
		var step := -zoom_step if event.is_action_pressed(ZOOM_IN) else zoom_step
		distance = clampf(distance + step, nearest, farthest)
		_apply()
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion := (event as InputEventMouseMotion).relative
		orbit(-motion.x * mouse_sensitivity, motion.y * mouse_sensitivity)


func _process(delta: float) -> void:
	if not current:
		return
	var stick := Input.get_vector(DriverView.LOOK_LEFT, DriverView.LOOK_RIGHT, DriverView.LOOK_UP,
		DriverView.LOOK_DOWN)
	if stick != Vector2.ZERO:
		orbit(-stick.x * stick_speed * delta, stick.y * stick_speed * delta)


## Places it on its orbit, looking at the pivot over the car.
func _apply() -> void:
	var turn := Basis.from_euler(Vector3(-pitch, yaw, 0.0))
	transform = Transform3D(turn, Vector3(0.0, pivot_height, 0.0) + turn * Vector3(0.0, 0.0,
		distance))
