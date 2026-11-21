@tool
class_name Prop
extends Node3D
## A solid object on the map, from a preset: a parked car or van, a cone, a barrier, a bollard, a
## building, a tree, a fence panel, a planter, or a crate. Most presets show a Kenney model (see
## [KitModels]), [member variant] picking among a preset's models; the barrier and the bollard are
## plain shapes. It builds a static body of its [method body_type] with a box around the model, so
## the player's car collides with it, road users see it, and [ContactCheck] judges touching it.

enum Preset { PARKED_CAR, VAN, CONE, BARRIER, BOLLARD, BUILDING, TREE, SMALL_TREE, FENCE, PLANTER,
	CRATE }

@export var preset := Preset.PARKED_CAR:
	set(value):
		preset = value
		_queue_rebuild()
## Which of the preset's models: a car, van, or house of the kit; it wraps round.
@export var variant := 0:
	set(value):
		variant = value
		_queue_rebuild()
## The colour of a preset without a model.
@export var colour := Color(0.7, 0.2, 0.15):
	set(value):
		colour = value
		_queue_rebuild()
## Width, height, and depth of a building, metres: its house is stretched to the width and depth,
## and its height follows.
@export var building_size := Vector3(10, 8, 10):
	set(value):
		building_size = value
		_queue_rebuild()

## The collision box of the presets without a model.
const BOXES := {
	Preset.BARRIER: Vector3(2.0, 1.0, 0.3),
	Preset.BOLLARD: Vector3(0.25, 1.0, 0.25),
}
## The size cars and vans are stretched to, metres: the kit's are wider and taller than real ones.
const FITS := {
	Preset.PARKED_CAR: Vector3(1.8, 1.5, 4.3),
	Preset.VAN: Vector3(2.0, 2.2, 5.2),
}
## How much taller trees stand than the kit has them: its trees are slim saplings.
const TREE_SCALE := 1.6
## How much of a tree's model is its trunk, which is what is solid.
const TRUNK := Vector3(0.45, 1.0, 0.45)
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


## The model this prop shows; empty for a plain shape.
func model() -> String:
	return model_of(preset, variant)


## The model [param of_preset] shows with [param of_variant]; empty for a plain shape.
static func model_of(of_preset: Preset, of_variant := 0) -> String:
	match of_preset:
		Preset.PARKED_CAR: return KitModels.car(of_variant)
		Preset.VAN: return KitModels.van(of_variant)
		Preset.CONE: return KitModels.car_kit("cone")
		Preset.BUILDING: return KitModels.building(of_variant)
		Preset.TREE: return KitModels.suburban("tree-large")
		Preset.SMALL_TREE: return KitModels.suburban("tree-small")
		Preset.FENCE: return KitModels.suburban("fence")
		Preset.PLANTER: return KitModels.suburban("planter")
		Preset.CRATE: return KitModels.car_kit("box")
	return ""


## The collision box's size.
func box_size() -> Vector3:
	if BOXES.has(preset):
		return BOXES[preset]
	var size := _model_scale() * KitModels.size_of(model())
	if preset == Preset.TREE or preset == Preset.SMALL_TREE:
		size *= TRUNK
	return size.max(Vector3.ONE * 0.1)


## What kind of solid it is: a parked car or van is a vehicle, anything else an obstacle.
func body_type() -> BodyType:
	var vehicle := preset == Preset.PARKED_CAR or preset == Preset.VAN
	return BodyType.of(&"vehicle" if vehicle else &"obstacle")


func rebuild() -> void:
	_rebuild_queued = false
	if _body:
		remove_child(_body)
		_body.queue_free()
	_body = StaticBody3D.new()
	_body.name = "Body"
	body_type().apply(_body)
	var size := box_size()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	shape.position.y = size.y / 2.0
	_body.add_child(shape)
	var path := model()
	var built := KitModels.mesh(path) if not path.is_empty() else null
	if built:
		var part := MeshInstance3D.new()
		part.mesh = built
		part.scale = _model_scale()
		_body.add_child(part)
	elif preset == Preset.BOLLARD:
		var post := CylinderMesh.new()
		post.top_radius = size.x / 2.0
		post.bottom_radius = size.x / 2.0
		post.height = size.y
		_mesh(post, CONCRETE, size.y / 2.0)
	elif preset == Preset.BARRIER:
		_mesh(_box(size), Color(0.9, 0.9, 0.9), size.y / 2.0)
	else:
		_mesh(_box(size), colour, size.y / 2.0)
	add_child(_body, false, INTERNAL_MODE_BACK)


## How the model is stretched: a car or van to [constant FITS], a tree by
## [constant TREE_SCALE], a building to its size, every other model as the kit has it.
func _model_scale() -> Vector3:
	var size := KitModels.size_of(model())
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		return Vector3.ONE
	if FITS.has(preset):
		return (FITS[preset] as Vector3) / size
	if preset == Preset.TREE or preset == Preset.SMALL_TREE:
		return Vector3.ONE * TREE_SCALE
	if preset != Preset.BUILDING:
		return Vector3.ONE
	var across := Vector2(building_size.x / size.x, building_size.z / size.z)
	return Vector3(across.x, (across.x + across.y) / 2.0, across.y)


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
