@tool
class_name TriggerZone
extends Area3D
## A region of the road, authored as a box [CollisionShape3D] child: what a check watches, what
## starts a light or a road user, or the area of a [Crossing]. When the scenario loads, a [Bake] turns it into a zone entity, and the zone system decides by geometry
## whether the car is in it; the node itself detects nothing at runtime.
##
## In the editor it fills its box with a translucent colour by role, so a scenario reads at a
## glance: green for a goal, blue for a junction exit, yellow for no parking, red where the car
## must give way or stop (a crossing included), and orange for any other zone. [member editor_colour] overrides it.

const GOAL := Color(0.2, 0.85, 0.3, 0.25)
const EXIT := Color(0.25, 0.5, 1.0, 0.25)
const NO_PARKING := Color(0.95, 0.8, 0.1, 0.25)
const YIELD := Color(0.95, 0.2, 0.15, 0.25)
const OTHER := Color(1.0, 0.55, 0.1, 0.2)

## The editor fill; fully transparent to pick it by role.
@export var editor_colour := Color(0, 0, 0, 0)

var _box: CollisionShape3D
var _preview: MeshInstance3D


func _ready() -> void:
	if Engine.is_editor_hint():
		_preview = MeshInstance3D.new()
		add_child(_preview, false, INTERNAL_MODE_BACK)
		return
	set_process(false)
	collision_layer = 0
	collision_mask = 0
	monitoring = false
	monitorable = false


## The zone's box: its transform and half extents; null when it has no box shape.
func box_data() -> Variant:
	var shape := _box_shape()
	if shape == null:
		return null
	return [shape.global_transform, shape.shape.size * 0.5]


## The fill this zone shows in the editor.
func role_colour() -> Color:
	if editor_colour.a > 0.0:
		return editor_colour
	if self is JunctionExit:
		return EXIT
	if self is NoParkingZone:
		return NO_PARKING
	var parent := get_parent()
	if parent is GoalCheck:
		return GOAL
	if parent is YieldCheck or parent is CrossingCheck or parent is StopCheck \
			or parent is TrafficLightCheck or parent is Crossing:
		return YIELD
	return OTHER


func _get_configuration_warnings() -> PackedStringArray:
	if _box_shape() == null:
		return ["Add a CollisionShape3D child with a box shape."]
	return []


func _process(_delta: float) -> void:
	# Editor only: keeps the fill on the box as it is edited.
	if _preview == null:
		return
	var box := _box_shape()
	_preview.visible = box != null
	if box == null:
		return
	var mesh := _preview.mesh as BoxMesh
	if mesh == null:
		mesh = BoxMesh.new()
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh.material = material
		_preview.mesh = mesh
	mesh.size = box.shape.size
	(mesh.material as StandardMaterial3D).albedo_color = role_colour()
	_preview.transform = box.transform


func _box_shape() -> CollisionShape3D:
	if _box == null or not is_instance_valid(_box) or _box.get_parent() != self:
		_box = null
		for child in get_children():
			if child is CollisionShape3D and child.shape is BoxShape3D:
				_box = child
				break
	return _box

