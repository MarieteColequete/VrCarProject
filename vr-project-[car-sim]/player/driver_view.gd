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
## Seconds both grips are held, away from the wheel, to recentre the seat in VR; with a real
## steering wheel, holding its rim at a quarter to three, to line the car's up with it.
@export var recentre_hold := 2.0
## The settings file the seat's shift onto a real wheel is kept in ([method align_seat]).
@export var controls_path := WheelInput.PATH
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
## The mirror tilt controls: the arrow keys, and the D-pad (where they wait on its other jobs).
const TILT_LEFT := &"mirror_tilt_left"
const TILT_RIGHT := &"mirror_tilt_right"
const TILT_UP := &"mirror_tilt_up"
const TILT_DOWN := &"mirror_tilt_down"
## How far a grip is squeezed to hold, and a stick pushed to flick, 0 to 1.
const GRIP_HOLD := 0.6
const FLICK := 0.7
## The settings section the seat's shift onto a real wheel is kept under.
const VR_SECTION := "vr"
## What a flick of the left stick does in VR, as the gamepad's D-pad: by the way it is flicked
## ([method flick_of]).
const DPAD_JOBS := {Vector2i(-1, 0): DriverInput.INDICATOR_LEFT,
	Vector2i(1, 0): DriverInput.INDICATOR_RIGHT, Vector2i(0, 1): &"exam_restart",
	Vector2i(0, -1): &"exam_next"}

## Radians; 0 looks straight ahead.
var yaw := 0.0
var pitch := 0.0
## True while the headset drives the view.
var vr := false
## In VR, the window shows the instructor's [SpectatorView] while the headset shows the driver's;
## on a standalone headset there is no window, and no spectator.
var spectator_enabled := true
## The instructor's view on the window, in VR on a desktop; null otherwise.
var spectator: SpectatorView
## The viewport the headset renders, in VR with a spectator; else the window's own.
var headset: SubViewport
## The steering wheel in the driver's hands, in VR.
var wheel := WheelGrab.new()
## The mirrors in the driver's hands, in VR.
var mirror_grab := MirrorGrab.new()
## While the driver sets a mirror with the controls, the tilt controls and the look stick tilt it
## ([method mirror_look]) and leave the head where it is; the mouse still turns the head.
var look_locked := false
## The motion controllers in VR, left then right; empty otherwise.
var hands: Array[XRController3D] = []
## Where a real steering wheel drives the car, the car's own rim (its origin the rim's centre, as
## [method grab_wheel] takes it), for lining the seat up with the real one; null without one.
var real_rim: Variant = null
## How far the headset's room is shifted from the seat, in the seat's space, so the car's rim sits
## where a real wheel's is ([method align_seat]); kept between sessions.
var seat_offset := Vector3.ZERO
## Whether this view is the one shown; a car may switch to another camera.
var active := true:
	set = set_active

## The way the left stick was last flicked, as the D-pad: x left or right, y up or down.
var _flicked := Vector2i.ZERO
## The right stick pulled down: held, the park button; flicked, the lever down.
var _lever_down := HoldTap.new()
var _buttons := {}
var _both_grips := 0.0

@onready var flat_camera: Camera3D = $FlatCamera
@onready var xr_origin: XROrigin3D = $XROrigin3D
@onready var xr_camera: XRCamera3D = $XROrigin3D/XRCamera3D


func _ready() -> void:
	var xr := XRServer.find_interface("OpenXR")
	vr = xr != null and xr.is_initialized()
	if vr:
		if spectator_enabled and not OS.has_feature("android"):
			_split_headset(xr)
		else:
			get_viewport().use_xr = true
		xr_camera.cull_mask &= ~Layers.SPECTATOR_VISUAL
		XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, false)
		var config := ConfigFile.new()
		if config.load(controls_path) == OK:
			seat_offset = config.get_value(VR_SECTION, &"seat_offset", Vector3.ZERO)
		_place_room()
		# Godot only reports the runtime's request to close the application (closing it from the
		# headset's menu); OpenXR expects the process to end, and the game is VR only.
		if not xr.instance_exiting.is_connected(_on_instance_exiting):
			xr.instance_exiting.connect(_on_instance_exiting)
		_add_hands()
	elif capture_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	set_active(active)


## Gives the headset back to the window, where the menus render it, after a split
## ([method _split_headset]).
func _exit_tree() -> void:
	if headset and is_instance_valid(headset):
		get_viewport().use_xr = true


func _on_instance_exiting() -> void:
	get_tree().quit()


func set_active(value: bool) -> void:
	active = value
	if not is_node_ready():
		return
	if active:
		if vr:
			xr_camera.current = true
			if spectator:
				spectator.current = true
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
		XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, false)
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
	if headset:
		# The headset's origin lives in its own viewport; it rides with the seat.
		xr_origin.global_transform = get_global_transform_interpolated().translated_local(
			seat_offset)
	if not active:
		return
	if vr:
		_xr_controls(delta)
		return
	var stick := Input.get_vector(LOOK_LEFT, LOOK_RIGHT, LOOK_UP, LOOK_DOWN)
	if stick != Vector2.ZERO and not look_locked:
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


## What tilts a mirror while [member look_locked], as [method Input.get_vector] gives it (x to the
## right, y down): the tilt controls (the arrow keys, the D-pad) and the look stick, or in VR the
## right controller's stick.
func mirror_look() -> Vector2:
	var stick := Input.get_vector(LOOK_LEFT, LOOK_RIGHT, LOOK_UP, LOOK_DOWN) \
		+ Input.get_vector(TILT_LEFT, TILT_RIGHT, TILT_UP, TILT_DOWN)
	if vr and hands.size() == 2:
		var right := hands[1].get_vector2(&"primary")
		stick = Vector2(right.x, -right.y)
	return stick.limit_length(1.0)


## Takes the mirrors' glass at [param glasses] (world frames, facing their +Z) in the hands, after
## the steering wheel, a hand on the wheel taking no mirror: each mirror's tilt change (see
## [method MirrorGrab.step]). Without controllers no mirror is held.
func grab_mirrors(glasses: Array) -> Array[Vector2]:
	var none: Array[Vector2] = []
	none.resize(glasses.size())
	none.fill(Vector2.ZERO)
	if hands.size() < 2:
		return none
	var at: Array = []
	var grips: Array = []
	var on_wheel: Array = []
	for i in hands.size():
		at.append(hands[i].global_position)
		grips.append(hands[i].get_float(&"grip") > GRIP_HOLD)
		on_wheel.append(wheel.holds[i] != null)
	var r := mirror_grab.step(glasses, at, grips, on_wheel)
	for i in hands.size():
		if mirror_grab.holds[i] != null:
			var glove: Node3D = hands[i].get_node(^"Glove")
			glove.global_position = MirrorGrab.on_glass(glasses[mirror_grab.holds[i].mirror], at[i])
	if not (r.taken as Array).is_empty():
		pulse(0.25, 0.04)
	return r.tilts


## A buzz in both controllers of [param strength] (0 to 1) for [param seconds].
func pulse(strength: float, seconds: float) -> void:
	for hand in hands:
		hand.trigger_haptic_pulse(&"haptic", 0.0, strength, seconds, 0.0)


## Moves the headset into a viewport of its own sharing the world, as Godot's OpenXR spectator
## demo does, so the window can show the instructor's view and the game's on-screen displays. The
## window stops listening to 3D sound, which the headset's camera hears.
func _split_headset(xr: XRInterface) -> void:
	var window := get_viewport()
	# The window renders the instructor's view now; the menus' own XR on it comes back when the
	# driver's view leaves ([method _exit_tree]).
	window.use_xr = false
	headset = SubViewport.new()
	headset.name = "Headset"
	headset.use_xr = true
	headset.world_3d = window.find_world_3d()
	headset.size = xr.get_render_target_size()
	headset.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	headset.audio_listener_enable_3d = true
	add_child(headset)
	xr_origin.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	xr_origin.reparent(headset, false)
	xr_origin.global_transform = global_transform
	window.audio_listener_enable_3d = false
	spectator = SpectatorView.new()
	spectator.car = get_parent() as Node3D
	spectator.eye = xr_camera
	add_child(spectator)
	spectator.current = true


## The controllers, each with a glove drawn on the hands' visual layer, which mirrors leave out.
func _add_hands() -> void:
	for side in [&"left_hand", &"right_hand"]:
		var hand := XRController3D.new()
		hand.name = "LeftHand" if side == &"left_hand" else "RightHand"
		hand.tracker = side
		hand.pose = &"grip"
		# A controller the runtime does not track draws nothing, rather than a glove at the seat.
		hand.show_when_tracked = true
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


## The controllers as the car's controls, laid out as the gamepad: the right trigger is the
## throttle, the left the brake; right A the handbrake and right B the mirror switch
## ([MirrorAdjust]); left X the headlights, left Y held the key (and begin); the left menu button
## the menu; the left stick flicked the D-pad ([constant DPAD_JOBS]) and clicked the debug HUD; a
## flick of the right stick up or down the gear lever (held down, the park button), and its click
## recentres; holding both grips away from the wheel and the mirrors recentres too, or with a real
## steering wheel, its rim held, lines the car's rim up with it.
func _xr_controls(delta: float) -> void:
	if hands.size() < 2:
		return
	var left := hands[0]
	var right := hands[1]
	_hold(DriverInput.THROTTLE, right.get_float(&"trigger"))
	_hold(DriverInput.BRAKE, left.get_float(&"trigger"))
	# The face buttons are the gamepad's: right A and B are its A and B, left X and Y its X and Y.
	_hold(DriverInput.HANDBRAKE, 1.0 if right.is_button_pressed(&"ax_button") else 0.0)
	_edge(&"mirror", right.is_button_pressed(&"by_button"), MirrorAdjust.ACTION)
	_edge(&"headlights", left.is_button_pressed(&"ax_button"), DriverInput.HEADLIGHTS)
	var key := left.is_button_pressed(&"by_button")
	_hold(DriverInput.IGNITION, 1.0 if key else 0.0)
	_edge(&"begin", key, &"exam_begin")
	_edge(&"menu", left.is_button_pressed(&"menu_button"), &"menu")
	_edge(&"debug_hud", left.is_button_pressed(&"primary_click"), &"toggle_debug_hud")
	_edge(&"recentre", right.is_button_pressed(&"primary_click"), LOOK_RESET)
	# The left stick is the gamepad's D-pad, flicked: left and right the indicators, up restart,
	# down next.
	var flicked := flick_of(left.get_vector2(&"primary"))
	if flicked != Vector2i.ZERO and flicked != _flicked:
		_tap(DPAD_JOBS[flicked])
		pulse(0.3, 0.03)
	_flicked = flicked
	# A flick of the right stick up or down moves the gear lever, unless it sets a mirror; held down
	# half a second it is the park button, a quicker flick down moving the lever when let go.
	var lever := right.get_vector2(&"primary").y if not look_locked else 0.0
	_edge(&"shift_up", lever > FLICK, DriverInput.SHIFT_UP)
	if lever < -FLICK:
		if not _lever_down.down:
			_lever_down.press()
		if _lever_down.advance(delta):
			_tap(DriverInput.PARK)
	elif _lever_down.release():
		_tap(DriverInput.SHIFT_DOWN)
	var both := not wheel.held() and not mirror_grab.held() \
		and left.get_float(&"grip") > GRIP_HOLD \
		and right.get_float(&"grip") > GRIP_HOLD
	_both_grips = _both_grips + delta if both else 0.0
	if _both_grips >= recentre_hold:
		_both_grips = -INF
		if real_rim != null:
			align_seat(real_rim, (left.global_position + right.global_position) * 0.5)
		else:
			reset_look()
		pulse(0.5, 0.1)


## Lines the car's rim [param rim] up with a real wheel held at a quarter to three, its centre
## midway between the hands at [param hands_mid]: shifts the headset's room so the hands are on
## the car's rim, and keeps the shift.
func align_seat(rim: Transform3D, hands_mid: Vector3) -> void:
	seat_offset += seat_shift(global_transform, rim.origin, hands_mid)
	_place_room()
	var config := ConfigFile.new()
	config.load(controls_path)
	config.set_value(VR_SECTION, &"seat_offset", seat_offset)
	config.save(controls_path)


## The shift, in the space of [param seat], that takes a point at [param hands_mid] onto
## [param rim_centre].
static func seat_shift(seat: Transform3D, rim_centre: Vector3, hands_mid: Vector3) -> Vector3:
	return seat.basis.inverse() * (rim_centre - hands_mid)


## Places the headset's room at the seat, shifted by [member seat_offset].
func _place_room() -> void:
	if headset:
		xr_origin.global_transform = global_transform.translated_local(seat_offset)
	else:
		xr_origin.position = seat_offset


## The way a stick at [param stick] (y up, as a controller gives it) is flicked: one of the four
## directions once pushed past [constant FLICK], along its larger axis; none short of that.
static func flick_of(stick: Vector2) -> Vector2i:
	if stick.length() < FLICK:
		return Vector2i.ZERO
	if absf(stick.x) >= absf(stick.y):
		return Vector2i(int(signf(stick.x)), 0)
	return Vector2i(0, int(signf(stick.y)))


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
