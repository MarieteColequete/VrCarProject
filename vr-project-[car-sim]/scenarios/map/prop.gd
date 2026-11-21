@tool
class_name Prop
extends Node3D
## A solid object on the map, from a preset: a parked car or van, a cone, a barrier, a bollard, a
## building, or a tree. It builds a static body on the obstacle layer, so the player's car collides
## with it, road users see it, and [ContactCheck] judges touching it.

enum Preset { PARKED_CAR, VAN, CONE, BARRIER, BOLLARD, BUILDING, TREE }

@export var preset := Preset.PARKED_CAR:
	set(value):
		preset = value
		_queue_rebuild()
@export var colour := Color(0.7, 0.2, 0.15):
	set(value):
		colour = value
		_queue_rebuild()
## Width, height, and depth of a building, metres.
@export var building_size := Vector3(10, 8, 10):
	set(value):
		building_size = value
		_queue_rebuild()

## Per preset: the collision box, and how high its centre sits.
const BOXES := {
	Preset.PARKED_CAR: Vector3(1.8, 1.4, 4.2),
	Preset.VAN: Vector3(2.0, 2.4, 5.4),
	Preset.CONE: Vector3(0.4, 0.7, 0.4),
	Preset.BARRIER: Vector3(2.0, 1.0, 0.3),
	Preset.BOLLARD: Vector3(0.25, 1.0, 0.25),
	Preset.TREE: Vector3(0.4, 3.0, 0.4),
}
const CONE_ORANGE := Color(1.0, 0.45, 0.05)
const BARK := Color(0.4, 0.27, 0.15)
const LEAVES := Color(0.2, 0.5, 0.2)
const CONCRETE := Color(0.7, 0.7, 0.68)

var _body: StaticBody3D
var _rebuild_queued := false


func _ready() -> void:
	rebuild()


## The prop's bodies, for the bake to turn into obstacles: they are internal children, which a
## scene walk leaves out.
func bodies() -> Array[StaticBody3D]:
	var out: Array[StaticBody3D] = []
	if _body:
		out.append(_body)
	return out


## The collision box's size.
func box_size() -> Vector3:
	return building_size if preset == Preset.BUILDING else BOXES[preset]


func rebuild() -> void:
	_rebuild_queued = false
	if _body:
		remove_child(_body)
		_body.queue_free()
	_body = StaticBody3D.new()
	_body.name = "Body"
	_body.collision_layer = Layers.OBSTACLE
	_body.collision_mask = 0
	var size := box_size()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y / 2.0
	_body.add_child(shape)
	match preset:
		Preset.CONE:
			var cone := CylinderMesh.new()
			cone.top_radius = 0.03
			cone.bottom_radius = 0.2
			cone.height = size.y
			_mesh(cone, CONE_ORANGE, size.y / 2.0)
		Preset.BOLLARD:
			var post := CylinderMesh.new()
			post.top_radius = size.x / 2.0
			post.bottom_radius = size.x / 2.0
			post.height = size.y
			_mesh(post, CONCRETE, size.y / 2.0)
		Preset.TREE:
			var trunk := CylinderMesh.new()
			trunk.top_radius = 0.15
			trunk.bottom_radius = 0.2
			trunk.height = size.y
			_mesh(trunk, BARK, size.y / 2.0)
			var crown := SphereMesh.new()
			crown.radius = 1.8
			crown.height = 3.2
			_mesh(crown, LEAVES, size.y + 1.0)
		Preset.BARRIER:
			_mesh(_box(size), Color(0.9, 0.9, 0.9), size.y / 2.0)
		_:
			_mesh(_box(size), colour, size.y / 2.0)
	add_child(_body, false, INTERNAL_MODE_BACK)


func _queue_rebuild() -> void:
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	rebuild.call_deferred()


static func _box(size: Vector3) -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh


func _mesh(mesh: Mesh, tint: Color, y: float) -> void:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	part.material_override = material
	part.position.y = y
	_body.add_child(part)
