@tool
class_name Checkpoint
extends Marker3D
## A point on the map a road user drives to: a [ScriptedAgent] with it as its
## [member ScriptedAgent.destination] takes the shortest way along the lanes to the lane passing
## nearest it and stops there, reacting to traffic on the way. In the editor it draws a ring on
## the ground and a flag; in the game it is not shown.

## A name menus and the overlay may show, such as "Station car park".
@export var label := ""

## Radius of the ring drawn in the editor, metres.
const RING := 2.0
const COLOUR := Color(0.95, 0.35, 0.9)

var _preview: MeshInstance3D


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	_preview = MeshInstance3D.new()
	add_child(_preview, false, INTERNAL_MODE_BACK)
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var sides := 32
	for i in sides:
		for k in [i, i + 1]:
			var angle: float = TAU * k / sides
			mesh.surface_add_vertex(Vector3(cos(angle) * RING, 0.05, sin(angle) * RING))
	for pair: Array in [[Vector3(0, 0, 0), Vector3(0, 2.5, 0)], [Vector3(0, 2.5, 0),
			Vector3(0.9, 2.2, 0)], [Vector3(0.9, 2.2, 0), Vector3(0, 1.9, 0)]]:
		mesh.surface_add_vertex(pair[0])
		mesh.surface_add_vertex(pair[1])
	mesh.surface_end()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = COLOUR
	mesh.surface_set_material(0, material)
	_preview.mesh = mesh
