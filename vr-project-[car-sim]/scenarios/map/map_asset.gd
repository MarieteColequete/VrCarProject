@tool
class_name MapAsset
extends Node3D
## Any model of [code]res://assets/[/code] on the map, as the Asset Library pane places it (see
## [AssetCatalogue]): its mesh at the pack's size, stretched to [member fit] or scaled by
## [member extra_scale]; with a [member body_type], a static body of that type with a box around
## [member solid_part] of it (or the model's own surface, for [member mesh_collider]), so the
## player's car collides with it and, for a judged type such as an obstacle or a vehicle, road
## users see it and [ContactCheck] judges touching it. Its settings are saved with the map, so later changes to a
## pack's categories leave placed models as they are.

## The model's [code].glb[/code].
@export_file("*.glb") var model := "":
	set(value):
		model = value
		_queue_rebuild()
## What kind of solid it is; none for looks only.
@export var body_type: BodyType = OBSTACLE:
	set(value):
		body_type = value
		_queue_rebuild()
## Collide with the model's own surface instead of a box: for ground pieces such as road tiles,
## whose kerbs stand up and whose asphalt is flat.
@export var mesh_collider := false:
	set(value):
		mesh_collider = value
		_queue_rebuild()
## The size to stretch the model to, metres; zero on an axis keeps the pack's size there.
@export var fit := Vector3.ZERO:
	set(value):
		fit = value
		_queue_rebuild()
## A further scale on the pack's, where [member fit] is zero.
@export var extra_scale := 1.0:
	set(value):
		extra_scale = value
		_queue_rebuild()
## The part of the model's box that is solid, per axis, centred.
@export var solid_part := Vector3.ONE:
	set(value):
		solid_part = value
		_queue_rebuild()

const OBSTACLE := preload("res://scenarios/data/body_types/obstacle.tres")
## The settings a model's category gives it, which replacing a model or stepping to its next look
## sets together.
const SETTINGS: Array[StringName] = [&"model", &"body_type", &"mesh_collider", &"fit",
	&"extra_scale", &"solid_part"]
## How see-through a [member preview] is drawn.
const PREVIEW_TRANSPARENCY := 0.45

## Drawn see-through with no body, as the Map Kit's placer shows a model before it is placed: it
## stops no ray and bakes into nothing. Not saved.
var preview := false:
	set(value):
		preview = value
		_queue_rebuild()

var _body: StaticBody3D
var _part: MeshInstance3D
var _rebuild_queued := false


func _ready() -> void:
	rebuild()


## [param model_name], a file name such as [code]building-type-a[/code], to show: "Building type
## a".
static func label_of(model_name: String) -> String:
	var words := model_name.replace("-", " ").replace("_", " ")
	return words.left(1).to_upper() + words.substr(1)


## The body for the bake to turn into an obstacle; empty when it is not solid.
func bodies() -> Array[StaticBody3D]:
	var out: Array[StaticBody3D] = []
	if _body:
		out.append(_body)
	return out


## The model's size as shown, metres; zero when it does not load.
func size() -> Vector3:
	return KitModels.size_of(model) * model_scale()


## The scale the model is shown at.
func model_scale() -> Vector3:
	return scale_for(KitModels.size_of(model), fit, extra_scale)


## The scale a model of [param natural] size is shown at, stretched to [param p_fit] where it is
## not zero, and scaled by [param p_extra] elsewhere.
static func scale_for(natural: Vector3, p_fit: Vector3, p_extra: float) -> Vector3:
	var out := Vector3.ONE * p_extra
	for axis in 3:
		if p_fit[axis] > 0.0 and natural[axis] > 0.0:
			out[axis] = p_fit[axis] / natural[axis]
	return out


func rebuild() -> void:
	_rebuild_queued = false
	if not is_inside_tree():
		return
	for old: Node in [_body, _part]:
		if old and is_instance_valid(old):
			remove_child(old)
			old.queue_free()
	_body = null
	_part = null
	var mesh := KitModels.mesh(model) if not model.is_empty() else null
	if mesh == null:
		return
	_part = MeshInstance3D.new()
	_part.mesh = mesh
	_part.scale = model_scale()
	if preview:
		_part.transparency = PREVIEW_TRANSPARENCY
	add_child(_part, false, INTERNAL_MODE_BACK)
	if body_type == null or preview:
		return
	_body = StaticBody3D.new()
	_body.name = "Body"
	body_type.apply(_body)
	var shape := CollisionShape3D.new()
	if mesh_collider:
		var faces := mesh.get_faces()
		var scaled := model_scale()
		for i in faces.size():
			faces[i] *= scaled
		var surface := ConcavePolygonShape3D.new()
		surface.set_faces(faces)
		shape.shape = surface
	else:
		var box := BoxShape3D.new()
		box.size = (size() * solid_part).max(Vector3.ONE * 0.1)
		shape.shape = box
		shape.position.y = box.size.y / 2.0
	_body.add_child(shape)
	add_child(_body, false, INTERNAL_MODE_BACK)


func _queue_rebuild() -> void:
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	rebuild.call_deferred()


## Maps saved before body types said [code]solid = false[/code] for looks only.
func _set(property: StringName, value: Variant) -> bool:
	if property == &"solid":
		body_type = OBSTACLE if value else null
		return true
	return false


func _get_configuration_warnings() -> PackedStringArray:
	if model.is_empty():
		return ["Pick a model in the Asset Library pane, or set one."]
	if KitModels.mesh(model) == null:
		return ["The model %s does not load." % model]
	return []
