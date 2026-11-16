class_name DriverView
extends Node3D
## The driver's eyes, placed at the driver's head in a car scene. With an OpenXR headset running,
## the headset drives the view. Otherwise a flat camera looks around the same way, turned by the
## mouse (while captured) and the right stick, within what a seated driver can turn.

@export var mouse_sensitivity := 0.0025
## Turn rate at full stick deflection, in radians per second.
@export var stick_speed := 2.5
@export var max_yaw_degrees := 120.0
@export var min_pitch_degrees := -60.0
@export var max_pitch_degrees := 60.0
## Captures the mouse when the view starts; a click recaptures it and release_mouse frees it.
@export var capture_mouse := true
## Mouse motion turns the view only while the mouse is captured.
@export var require_capture := true

const LOOK_LEFT := &"look_left"
const LOOK_RIGHT := &"look_right"
const LOOK_UP := &"look_up"
const LOOK_DOWN := &"look_down"
const LOOK_RESET := &"look_reset"
const RELEASE_MOUSE := &"release_mouse"
const VIEW_ACTIONS: Array[StringName] = [
	LOOK_LEFT, LOOK_RIGHT, LOOK_UP, LOOK_DOWN, LOOK_RESET, RELEASE_MOUSE]

## Radians; 0 looks straight ahead.
var yaw := 0.0
var pitch := 0.0
## True while the headset drives the view.
var vr := false
## Whether this view is the one shown; a car may switch to another camera.
var active := true:
	set = set_active

@onready var flat_camera: Camera3D = $FlatCamera
@onready var xr_origin: XROrigin3D = $XROrigin3D
@onready var xr_camera: XRCamera3D = $XROrigin3D/XRCamera3D


func _ready() -> void:
	var xr := XRServer.find_interface("OpenXR")
	vr = xr != null and xr.is_initialized()
	if vr:
		get_viewport().use_xr = true
		XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)
	elif capture_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	set_active(active)


func set_active(value: bool) -> void:
	active = value
	if not is_node_ready():
		return
	if active:
		if vr:
			xr_camera.current = true
		else:
			flat_camera.current = true


## The direction the driver is looking, in world space, in either mode.
func look_direction() -> Vector3:
	var camera: Node3D = xr_camera if vr else flat_camera
	return -camera.global_basis.z


func reset_look() -> void:
	if vr:
		XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)
	yaw = 0.0
	pitch = 0.0
	_apply()


## Turns the flat view by the given angles, in radians, within the limits.
func turn(delta_yaw: float, delta_pitch: float) -> void:
	yaw = clampf(yaw + delta_yaw, -deg_to_rad(max_yaw_degrees), deg_to_rad(max_yaw_degrees))
	pitch = clampf(pitch + delta_pitch,
		deg_to_rad(min_pitch_degrees), deg_to_rad(max_pitch_degrees))
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	if not active:
		return
	if event.is_action_pressed(LOOK_RESET):
		reset_look()
	elif event.is_action_pressed(RELEASE_MOUSE):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and capture_mouse and not vr:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventMouseMotion and not vr:
		if not require_capture or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
			turn(-event.relative.x * mouse_sensitivity, -event.relative.y * mouse_sensitivity)


func _process(delta: float) -> void:
	if not active or vr:
		return
	var stick := Input.get_vector(LOOK_LEFT, LOOK_RIGHT, LOOK_UP, LOOK_DOWN)
	if stick != Vector2.ZERO:
		turn(-stick.x * stick_speed * delta, -stick.y * stick_speed * delta)


func _apply() -> void:
	flat_camera.rotation = Vector3(pitch, yaw, 0.0)
