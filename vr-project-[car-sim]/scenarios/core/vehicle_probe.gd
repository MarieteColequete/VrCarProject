class_name VehicleProbe
extends Node3D
## The adapter between a car and the scenario checks. Added as a child of the car's body, it
## derives the car's motion from its own transform each physics tick, so it works with any car
## implementation; state the transform cannot show (the indicator) is set by the car.
##
## It also carries the contact hull: an [Area3D] slightly larger than the car that reports
## touching obstacles and pedestrians, whatever kind of body the car is.

## Emitted when the contact hull starts touching an obstacle or pedestrian.
signal contact_started(body: Node3D)

enum Indicator { UNKNOWN, OFF, LEFT, RIGHT, HAZARD }

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

## Set by the car; [constant Indicator.UNKNOWN] while the car does not report it.
var indicator := Indicator.UNKNOWN

## World-space velocity, metres per second.
var velocity := Vector3.ZERO
## Signed speed along the car's forward axis; negative when reversing.
var speed := 0.0

var _last_position := Vector3.ZERO
var _has_last := false
var _hull: Area3D


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


func _physics_process(delta: float) -> void:
	var pos := global_position
	if _has_last and delta > 0.0:
		velocity = (pos - _last_position) / delta
		speed = velocity.dot(forward())
	_last_position = pos
	_has_last = true


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
