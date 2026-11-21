@tool
class_name Scenery
extends Node3D
## Ground dressing from the suburban kit (see [KitModels]): a footpath, a stone path, or a
## driveway. It is looks only: nothing collides with it and nothing judges it, so it lies on the
## ground beside or across roads freely. Footpaths and driveways are slabs a few centimetres high.

enum Kind { PATH_LONG, PATH_SHORT, STONE_PATH_LONG, STONE_PATH_SHORT, STONE_PATH_MESSY,
	DRIVEWAY_LONG, DRIVEWAY_SHORT }

const MODELS := {
	Kind.PATH_LONG: "path-long", Kind.PATH_SHORT: "path-short",
	Kind.STONE_PATH_LONG: "path-stones-long", Kind.STONE_PATH_SHORT: "path-stones-short",
	Kind.STONE_PATH_MESSY: "path-stones-messy", Kind.DRIVEWAY_LONG: "driveway-long",
	Kind.DRIVEWAY_SHORT: "driveway-short",
}
## Height above the ground, metres, so it does not flicker with it.
const LIFT := 0.015

@export var kind := Kind.PATH_LONG:
	set(value):
		kind = value
		_rebuild()

var _part: MeshInstance3D


func _ready() -> void:
	_rebuild()


## The model this piece shows.
func model() -> String:
	return KitModels.suburban(MODELS[kind])


func _rebuild() -> void:
	if not is_inside_tree():
		return
	if _part == null:
		_part = MeshInstance3D.new()
		_part.position.y = LIFT
		add_child(_part, false, INTERNAL_MODE_BACK)
	_part.mesh = KitModels.mesh(model())
