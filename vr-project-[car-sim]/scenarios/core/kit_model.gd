@tool
class_name KitModel
extends MeshInstance3D
## Shows one of the [KitModels] on its origin, at the kit's size or stretched to
## [member fit]. The mesh is built when the node enters the tree and is not saved with the scene,
## so a scene using it stays small.

## The model's [code].glb[/code] in [code]res://assets/kenney/[/code].
@export_file("*.glb") var model := "":
	set(value):
		model = value
		_refresh()
## The size to stretch the model to, metres; zero on an axis keeps the kit's size there.
@export var fit := Vector3.ZERO:
	set(value):
		fit = value
		_refresh()


func _ready() -> void:
	_refresh()


func _validate_property(property: Dictionary) -> void:
	if property.name == "mesh":
		property.usage &= ~PROPERTY_USAGE_STORAGE


func _refresh() -> void:
	if not is_inside_tree() and mesh != null:
		return
	mesh = KitModels.mesh(model) if not model.is_empty() else null
	scale = Vector3.ONE
	if mesh == null:
		return
	var size := mesh.get_aabb().size
	for axis in 3:
		if fit[axis] > 0.0 and size[axis] > 0.0:
			scale[axis] = fit[axis] / size[axis]
