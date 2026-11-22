class_name SpectatorView
extends Camera3D
## The instructor's view on the desktop's window while the driver is in the headset: following the
## car from behind and above, or from behind the driver's shoulder, steadied so it turns with the
## car but never pitches or rolls with it. toggle_view cycles the views. It sees everything the
## headset does and what only the spectator is shown ([constant Layers.SPECTATOR_VISUAL]); the
## game's on-screen displays draw over it, since they are the window's. Moved every frame, so it is
## drawn where it is, not interpolated.

enum Mode { CHASE, COCKPIT }

## Where each view stands from the car, in the car's space turned with it only round the vertical,
## and where it looks, metres.
const CHASE_FROM := Vector3(0.0, 3.0, 7.0)
const CHASE_AT := Vector3(0.0, 1.0, -4.0)
const COCKPIT_FROM := Vector3(0.25, 0.04, 0.3)
const COCKPIT_AT := Vector3(0.0, -0.4, -10.0)
## How quickly the chase view catches up with the car, per second.
const FOLLOW := 5.0

var mode := Mode.CHASE
## The car followed.
var car: Node3D
## The driver's eye, which the cockpit view stands behind.
var eye: Node3D

var _placed := false


func _init() -> void:
	name = "SpectatorView"
	# It stands where it is put, not where the car carries it, so the chase view can lag.
	top_level = true
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	fov = 70.0
	near = 0.05


func _ready() -> void:
	_place(1.0)


## The next view: the chase view, then the driver's shoulder, then the chase view again.
func next_mode() -> void:
	mode = Mode.COCKPIT if mode == Mode.CHASE else Mode.CHASE
	_place(1.0)


func _process(delta: float) -> void:
	_place(1.0 - exp(-FOLLOW * delta))


## Where the view stands for the car's pose [param pose] in [param mode_now], the eye at
## [param at_eye]: [code]{from, at}[/code], both in world space, turned with the car's heading only.
static func spot(mode_now: Mode, pose: Transform3D, at_eye: Vector3) -> Dictionary:
	var ahead := -pose.basis.z
	ahead.y = 0.0
	var heading := Basis.looking_at(ahead.normalized() if ahead.length() > 0.001
		else Vector3.FORWARD, Vector3.UP)
	if mode_now == Mode.COCKPIT:
		return {from = at_eye + heading * COCKPIT_FROM, at = at_eye + heading * COCKPIT_AT}
	return {from = pose.origin + heading * CHASE_FROM, at = pose.origin + heading * CHASE_AT}


func _place(weight: float) -> void:
	if car == null or not is_instance_valid(car):
		return
	var pose := car.get_global_transform_interpolated()
	var at_eye := eye.global_position if eye and is_instance_valid(eye) else pose.origin
	var s := spot(mode, pose, at_eye)
	# The chase view eases after the car; the cockpit view sits with the driver.
	var from: Vector3 = s.from if mode == Mode.COCKPIT or not _placed \
		else global_position.lerp(s.from, weight)
	look_at_from_position(from, s.at, Vector3.UP)
	_placed = true
