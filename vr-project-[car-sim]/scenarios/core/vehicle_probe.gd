class_name VehicleProbe
extends Node3D
## The adapter between a car and the scenario checks. Added as a child of the car's body, it
## derives the car's motion from its own transform each physics tick, so it works with any car
## implementation; state the transform cannot show (indicator, handbrake, headlights) is set by
## the car, and stays unknown while the car does not report it. The footprint (body corners and
## wheel contact points) comes from the exported dimensions, and lines and parking are judged
## on it rather than on the car's centre.
##
## It also carries the contact hull: an [Area3D] slightly larger than the car that reports
## touching obstacles and pedestrians, whatever kind of body the car is.

## Emitted when the contact hull starts touching an obstacle or pedestrian.
signal contact_started(body: Node3D)
## Emitted when the car comes to a stop.
signal stopped
## Emitted when the car starts moving, forward or in reverse.
signal started_moving(direction: Direction)
## Emitted when the car moves off in the opposite direction to its last movement.
signal direction_changed(direction: Direction)

enum Indicator { UNKNOWN, OFF, LEFT, RIGHT, HAZARD }
enum Direction { STOPPED, FORWARD, REVERSE }
## A two-state control the car may or may not report.
enum Toggle { UNKNOWN, OFF, ON }

const VEHICLE_LAYER := 1 << 1
const OBSTACLE_LAYER := 1 << 2
const PEDESTRIAN_LAYER := 1 << 3
const DETECTION_LAYER := 1 << 4
const META_KEY := &"vehicle_probe"

## Size of the contact hull; match the car's body, plus a small margin.
@export var hull_size := Vector3(1.9, 1.5, 4.3)
## Height of the hull's centre above the probe.
@export var hull_height := 0.75
## Below this speed, in metres per second, the car counts as stopped.
@export var stop_speed := 0.3

@export_group("Footprint")
## Body length and width, in metres, centred on the probe.
@export var body_length := 4.2
@export var body_width := 1.8
## Distance between the front and rear axles, centred on the probe.
@export var wheelbase := 2.6
## Distance between the left and right wheels.
@export var track := 1.55
@export_group("")

## Set by the car; [constant Indicator.UNKNOWN] while the car does not report it.
var indicator := Indicator.UNKNOWN
var handbrake := Toggle.UNKNOWN
var headlights := Toggle.UNKNOWN

var direction := Direction.STOPPED
## How many times the car has moved off in the opposite direction to its last movement since the
## last [method reset]; the manoeuvre count of parking.
var direction_changes := 0

## World-space velocity, metres per second.
var velocity := Vector3.ZERO
## Signed speed along the car's forward axis; negative when reversing.
var speed := 0.0

var _last_position := Vector3.ZERO
var _has_last := false
var _hull: Area3D
var _last_moving := Direction.STOPPED
var _wheels := PackedVector3Array()
var _previous_wheels := PackedVector3Array()
var _driver_view: DriverView
var _clock := 0.0
var _indicator_seen := Indicator.UNKNOWN
var _indicator_since := 0.0


## The probe of a car body, or null.
static func of(body: Node) -> VehicleProbe:
	if body == null or not body.has_meta(META_KEY):
		return null
	return body.get_meta(META_KEY) as VehicleProbe


func _ready() -> void:
	get_parent().set_meta(META_KEY, self)
	_hull = Area3D.new()
	_hull.name = "ContactHull"
	_hull.collision_layer = DETECTION_LAYER
	_hull.collision_mask = OBSTACLE_LAYER | PEDESTRIAN_LAYER
	_hull.monitorable = false
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = hull_size
	shape.shape = box
	shape.position.y = hull_height
	_hull.add_child(shape)
	add_child(_hull)
	_hull.body_entered.connect(_on_hull_body_entered)
	for sibling in get_parent().get_children():
		if sibling is DriverView:
			_driver_view = sibling
	reset()


func _exit_tree() -> void:
	var parent := get_parent()
	if parent and VehicleProbe.of(parent) == self:
		parent.remove_meta(META_KEY)


## Forgets the previous position, so a teleport (a spawn or restart) does not read as speed.
func reset() -> void:
	_has_last = false
	velocity = Vector3.ZERO
	speed = 0.0
	direction = Direction.STOPPED
	_last_moving = Direction.STOPPED
	direction_changes = 0
	_wheels = PackedVector3Array()
	_previous_wheels = PackedVector3Array()


func _physics_process(delta: float) -> void:
	_clock += delta
	if indicator != _indicator_seen:
		_indicator_seen = indicator
		_indicator_since = _clock
	var pos := global_position
	if _has_last and delta > 0.0:
		velocity = (pos - _last_position) / delta
		speed = velocity.dot(forward())
	_last_position = pos
	_has_last = true
	_update_direction()
	_previous_wheels = _wheels if not _wheels.is_empty() else wheels()
	_wheels = wheels()


func _update_direction() -> void:
	var now := Direction.STOPPED
	if speed > stop_speed:
		now = Direction.FORWARD
	elif speed < -stop_speed:
		now = Direction.REVERSE
	if now == direction:
		return
	direction = now
	if now == Direction.STOPPED:
		stopped.emit()
		return
	started_moving.emit(now)
	if _last_moving != Direction.STOPPED and _last_moving != now:
		direction_changes += 1
		direction_changed.emit(now)
	_last_moving = now


## Seconds the indicator has shown [param side] without a break; 0 when it shows something else.
func indicator_held_for(side: Indicator) -> float:
	return _clock - _indicator_since if indicator == side and _indicator_seen == side else 0.0


## The four body corners on the ground, world space: front left, front right, rear right, rear
## left.
func corners() -> PackedVector3Array:
	return _ground_rect(body_width, body_length)


## The four wheel contact points, world space, in the same order as [method corners].
func wheels() -> PackedVector3Array:
	return _ground_rect(track, wheelbase)


## The wheel contact points one physics tick ago; equal to [method wheels] on the first tick. A
## wheel's movement this tick runs from here to [method wheels].
func previous_wheels() -> PackedVector3Array:
	return _previous_wheels if not _previous_wheels.is_empty() else wheels()


## Where the driver is looking, in world space: the car's [DriverView] when it has one, else the
## car's forward direction.
func look_direction() -> Vector3:
	if _driver_view and is_instance_valid(_driver_view):
		return _driver_view.look_direction()
	return forward()


func _ground_rect(width: float, length: float) -> PackedVector3Array:
	var hw := width * 0.5
	var hl := length * 0.5
	var out := PackedVector3Array()
	for local in [Vector3(-hw, 0, -hl), Vector3(hw, 0, -hl), Vector3(hw, 0, hl), Vector3(-hw, 0, hl)]:
		var p: Vector3 = global_transform * local
		p.y = global_position.y
		out.append(p)
	return out


## The car's forward direction, horizontal and normalised (Godot's -Z).
func forward() -> Vector3:
	var f := -global_basis.z
	f.y = 0.0
	return f.normalized()


func speed_kmh() -> float:
	return absf(speed) * 3.6


func is_stopped() -> bool:
	return absf(speed) < stop_speed


func _on_hull_body_entered(body: Node3D) -> void:
	if body == get_parent():
		return
	contact_started.emit(body)
