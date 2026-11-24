class_name VehicleProbe
extends Node3D
## The adapter between a car and the simulation. Added as a child of the car's body, it is where
## the shell reads the car each tick: the probe's transform is the car's pose, and the car sets
## what the transform cannot show (indicator, handbrake, headlights), which stays unknown while
## the car does not report it. The exported dimensions give the footprint lines and parking are
## judged on, and the contact hull, slightly larger than the body, that touches obstacles and
## pedestrians. The motion itself (speed, direction, stops) is derived by [VehicleLogic] from the
## pose alone, so any car implementation works.

enum Indicator { UNKNOWN, OFF, LEFT, RIGHT, HAZARD }
enum Direction { STOPPED, FORWARD, REVERSE }
## A two-state control the car may or may not report.
enum Toggle { UNKNOWN, OFF, ON }

const META_KEY := &"vehicle_probe"

## Size of the contact hull; match the car's body, plus a small margin.
@export var hull_size := Vector3(1.9, 1.5, 4.3)
## Height of the hull's centre above the probe.
@export var hull_height := 0.75
## Below this speed, in metres per second, the car counts as stopped.
@export var stop_speed := 0.3
## The car's mass, kilograms; a car with a spec sets its own.
@export var mass := 1250.0

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
## Where the car's mirrors are, in its own space: the interior mirror, then the left and right
## door mirrors; empty for a car without them. Set by the car.
var mirrors := PackedVector3Array()

var _driver_view: DriverView


## The probe of a car body, or null.
static func of(body: Node) -> VehicleProbe:
	if body == null or not body.has_meta(META_KEY):
		return null
	return body.get_meta(META_KEY) as VehicleProbe


func _ready() -> void:
	get_parent().set_meta(META_KEY, self)
	for sibling in get_parent().get_children():
		if sibling is DriverView:
			_driver_view = sibling


func _exit_tree() -> void:
	var parent := get_parent()
	if parent and VehicleProbe.of(parent) == self:
		parent.remove_meta(META_KEY)


## Where the driver is looking, in world space: the car's [DriverView] when it has one, else the
## car's forward direction.
func look_direction() -> Vector3:
	if _driver_view and is_instance_valid(_driver_view):
		return _driver_view.look_direction()
	return forward()


## Where the driver's eye is, in world space: the car's [DriverView]'s camera when it has one,
## else a seated driver's height above the probe.
func eye_position() -> Vector3:
	if _driver_view and is_instance_valid(_driver_view):
		return _driver_view.eye().global_position
	return global_position + Vector3.UP * 1.2


## The car's forward direction, horizontal and normalised (Godot's -Z).
func forward() -> Vector3:
	var f := -global_basis.z
	f.y = 0.0
	return f.normalized()


## The vehicle component's columns for this car now: its pose, what the car reports, and where the
## driver looks. The shell's vehicle input writes these each tick.
func reading() -> Dictionary:
	return {transform = global_transform, indicator = indicator, handbrake = handbrake,
		look = look_direction(), eye = eye_position()}


## The columns of a new vehicle entity for this car.
func spawn_values() -> Dictionary:
	var values := reading()
	values.merge({name = get_parent().name, body_length = body_length, body_width = body_width,
		wheelbase = wheelbase, track = track, hull_size = hull_size, hull_height = hull_height,
		stop_speed = stop_speed, mirrors = mirrors, mass = mass})
	return values
