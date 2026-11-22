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
## Seconds both grips are held, away from the wheel, to recentre the seat in VR.
@export var recentre_hold := 2.0
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
## How far a grip is squeezed to hold, and a stick pushed to flick, 0 to 1.
const GRIP_HOLD := 0.6
const FLICK := 0.7

## Radians; 0 looks straight ahead.
var yaw := 0.0
var pitch := 0.0
## True while the headset drives the view.
var vr := false
## The steering wheel in the driver's hands, in VR.
var wheel := WheelGrab.new()
## The motion controllers in VR, left then right; empty otherwise.
var hands: Array[XRController3D] = []
## Whether this view is the one shown; a car may switch to another camera.
var active := true:
	set = set_active

var _flicked := 0
var _buttons := {}
var _both_grips := 0.0

@onready var flat_camera: Camera3D = $FlatCamera
@onready var xr_origin: XROrigin3D = $XROrigin3D
@onready var xr_camera: XRCamera3D = $XROrigin3D/XRCamera3D


func _ready() -> void:
	var xr := XRServer.find_interface("OpenXR")
	vr = xr != null and xr.is_initialized()
	if vr:
		get_viewport().use_xr = true
		XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)
		# Godot only reports the runtime's request to close the application (closing it from the
		# headset's menu); OpenXR expects the process to end, and the game is VR only.
		if not xr.instance_exiting.is_connected(_on_instance_exiting):
			xr.instance_exiting.connect(_on_instance_exiting)
		_add_hands()
	elif capture_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	set_active(active)


func _on_instance_exiting() -> void:
	get_tree().quit()


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
	return -eye().global_basis.z


## The driver's eye: the headset's camera in VR, else the flat camera.
func eye() -> Node3D:
	return xr_camera if vr else flat_camera


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
	if not active:
		return
	if vr:
		_xr_controls(delta)
		return
	var stick := Input.get_vector(LOOK_LEFT, LOOK_RIGHT, LOOK_UP, LOOK_DOWN)
	if stick != Vector2.ZERO:
		turn(-stick.x * stick_speed * delta, -stick.y * stick_speed * delta)


func _apply() -> void:
	flat_camera.rotation = Vector3(pitch, yaw, 0.0)


## Takes the steering wheel at [param frame] (its origin the rim's centre, +Z the column pointing
## at the driver) of rim [param radius] in the hands for a step of [param delta] seconds, the car
## steering at [param current] when the hands take hold. Without controllers the wheel is never
## held.
func grab_wheel(delta: float, frame: Transform3D, radius: float, current: float) -> void:
	if hands.size() < 2:
		return
	var at: Array = []
	var grips: Array = []
	for hand in hands:
		at.append(hand.global_position)
		grips.append(hand.get_float(&"grip") > GRIP_HOLD)
	wheel.step(delta, frame, radius, at, grips, current)
	for i in hands.size():
		var glove: Node3D = hands[i].get_node(^"Glove")
		if wheel.holds[i] != null:
			glove.global_position = WheelGrab.on_rim(frame, radius, at[i])
		else:
			glove.position = Vector3.ZERO


## A buzz in both controllers of [param strength] (0 to 1) for [param seconds].
func pulse(strength: float, seconds: float) -> void:
	for hand in hands:
		hand.trigger_haptic_pulse(&"haptic", 0.0, strength, seconds, 0.0)


## The controllers, each with a glove drawn on the hands' visual layer, which mirrors leave out.
func _add_hands() -> void:
	for side in [&"left_hand", &"right_hand"]:
		var hand := XRController3D.new()
		hand.name = "LeftHand" if side == &"left_hand" else "RightHand"
		hand.tracker = side
		hand.pose = &"grip"
		hand.add_child(_glove(side == &"left_hand"))
		xr_origin.add_child(hand)
		hands.append(hand)


## A simple glove: a palm and a thumb, dark, on the hands' visual layer.
static func _glove(left: bool) -> Node3D:
	var glove := Node3D.new()
	glove.name = "Glove"
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.12, 0.12, 0.13)
	material.roughness = 0.8
	var palm := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.035, 0.09, 0.1)
	palm.mesh = box
	var thumb := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.012
	capsule.height = 0.06
	thumb.mesh = capsule
	thumb.position = Vector3(0.025 if left else -0.025, 0.03, -0.02)
	thumb.rotation = Vector3(deg_to_rad(60.0), 0.0, 0.0)
	for part: MeshInstance3D in [palm, thumb]:
		part.material_override = material
		part.layers = Layers.HANDS_VISUAL
		glove.add_child(part)
	return glove


## The controllers as the car's controls: the right trigger is the throttle, the left the brake,
## the right A the handbrake, the right B the headlights, a flick of the left stick an indicator,
## and the right stick's click recentres; holding both grips away from the wheel recentres too.
func _xr_controls(delta: float) -> void:
	if hands.size() < 2:
		return
	var left := hands[0]
	var right := hands[1]
	_hold(DriverInput.THROTTLE, right.get_float(&"trigger"))
	_hold(DriverInput.BRAKE, left.get_float(&"trigger"))
	_hold(DriverInput.HANDBRAKE, 1.0 if right.is_button_pressed(&"ax_button") else 0.0)
	var flick := left.get_vector2(&"primary").x
	var flicked := 0 if absf(flick) < FLICK else int(signf(flick))
	if flicked != 0 and flicked != _flicked:
		_tap(DriverInput.INDICATOR_LEFT if flicked < 0 else DriverInput.INDICATOR_RIGHT)
		pulse(0.3, 0.03)
	_flicked = flicked
	_edge(&"headlights", right.is_button_pressed(&"by_button"), DriverInput.HEADLIGHTS)
	_edge(&"recentre", right.is_button_pressed(&"primary_click"), LOOK_RESET)
	var both := not wheel.held() and left.get_float(&"grip") > GRIP_HOLD \
		and right.get_float(&"grip") > GRIP_HOLD
	_both_grips = _both_grips + delta if both else 0.0
	if _both_grips >= recentre_hold:
		_both_grips = -INF
		reset_look()
		pulse(0.5, 0.1)


func _hold(action: StringName, value: float) -> void:
	if value > 0.05:
		Input.action_press(action, value)
	elif Input.is_action_pressed(action):
		Input.action_release(action)


func _edge(key: StringName, down: bool, action: StringName) -> void:
	if down and not _buttons.get(key, false):
		_tap(action)
	_buttons[key] = down


## Sends [param action] as a press and a release, as a key would.
static func _tap(action: StringName) -> void:
	for pressed in [true, false]:
		var event := InputEventAction.new()
		event.action = action
		event.pressed = pressed
		Input.parse_input_event(event)
