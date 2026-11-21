@tool
class_name MapSpawn
extends Marker3D
## A place where the player's car may start, facing -Z of this node. A [RoadMap]'s first spawn is
## where free drive starts; a scenario may name another as its spawn point.
##
## In the editor it draws the outline of a car and an arrow in the direction of travel.

## A name menus may show, such as "North approach".
@export var label := ""

## Width and length of the outline, metres.
const OUTLINE := Vector2(1.8, 4.4)
const COLOUR := Color(0.3, 1.0, 0.45)

var _preview: MeshInstance3D


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	_preview = MeshInstance3D.new()
	add_child(_preview, false, INTERNAL_MODE_BACK)
	var half := OUTLINE / 2.0
	var y := 0.05
	var corners := [Vector3(-half.x, y, half.y), Vector3(half.x, y, half.y),
		Vector3(half.x, y, -half.y), Vector3(-half.x, y, -half.y)]
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var lines: Array = []
	for i in corners.size():
		lines.append([corners[i], corners[(i + 1) % corners.size()]])
	var tip := Vector3(0, y, -half.y - 1.0)
	lines.append([Vector3(-half.x, y, -half.y), tip])
	lines.append([Vector3(half.x, y, -half.y), tip])
	for line: Array in lines:
		for point: Vector3 in line:
			mesh.surface_set_color(COLOUR)
			mesh.surface_add_vertex(point)
	mesh.surface_end()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	mesh.surface_set_material(0, material)
	_preview.mesh = mesh
