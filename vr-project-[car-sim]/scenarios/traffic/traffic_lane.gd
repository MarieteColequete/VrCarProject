@tool
class_name TrafficLane
extends Path3D
## One lane of the road network, its curve along the lane's centre in the direction of traffic,
## and the rules road users on it obey: a road user on a lane keeps to its speed limit, continues
## onto one of its [member next] lanes at its end, stops at [member stop_offset] while its
## [member light] says so or while traffic on the lanes it gives way to is coming, and waits before
## any of its [member crossings] in use. Lanes are authored in the scene and baked to [LaneData];
## [LaneRules] evaluates them.
##
## In the editor the lane draws chevrons along its curve and a bar at its stop line.

## The highest speed on the lane, metres per second; 0 for none.
@export var speed_limit := 0.0
## The lanes traffic may continue onto at this lane's end.
@export var next: Array[TrafficLane] = []

@export_group("Rules")
## The light that controls the stop line.
@export var light: TrafficLight
## The lanes with priority over this one at the stop line.
@export var give_way_to: Array[TrafficLane] = []
## Metres along the lane of the stop line for the light and for giving way; negative for the
## lane's end.
@export var stop_offset := -1.0
## Seconds of clear road on the priority lanes that pulling out needs.
@export var safe_gap := 4.0
## Pedestrian crossings on the lane, [Crossing] nodes; traffic waits before one in use. Typed as
## plain nodes so the lane, its road users, and the crossing do not load in a cycle.
@export var crossings: Array[Node] = []

@export_group("Neighbours")
## The lanes beside this one, to change into when this one is blocked.
@export var left: TrafficLane
@export var right: TrafficLane
@export_group("")

const LANE_COLOUR := Color(0.3, 0.8, 1.0)
const STOP_COLOUR := Color(1.0, 0.3, 0.2)

var _preview: MeshInstance3D


func _ready() -> void:
	if Engine.is_editor_hint():
		_preview = MeshInstance3D.new()
		add_child(_preview, false, INTERNAL_MODE_BACK)
		if not curve_changed.is_connected(_draw_preview):
			curve_changed.connect(_draw_preview)
		_draw_preview()


func length() -> float:
	return curve.get_baked_length() if curve else 0.0


## The stop line's distance along the lane.
func stop_at() -> float:
	return stop_offset if stop_offset >= 0.0 else length()


## The point [param offset] metres along the lane, world space.
func point_at(offset: float) -> Vector3:
	return global_transform * curve.sample_baked(clampf(offset, 0.0, length()))


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if curve == null or curve.point_count < 2:
		warnings.append("Draw the lane's curve in the direction of traffic.")
	for crossing in crossings:
		if crossing == null or not crossing is Crossing:
			warnings.append("Crossings must be Crossing nodes.")
			break
	return warnings


func _draw_preview() -> void:
	if _preview == null or curve == null or length() <= 0.0:
		return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var total := length()
	var offset := 1.0
	while offset < total:
		var here := curve.sample_baked(offset)
		var ahead := curve.sample_baked(minf(offset + 0.5, total))
		var dir := ahead - here
		dir.y = 0.0
		if dir.length() > 0.001:
			dir = dir.normalized()
			var side := dir.cross(Vector3.UP) * 0.5
			var tip := here + dir * 0.6 + Vector3.UP * 0.1
			for wing in [here - side + Vector3.UP * 0.1, here + side + Vector3.UP * 0.1]:
				mesh.surface_set_color(LANE_COLOUR)
				mesh.surface_add_vertex(wing)
				mesh.surface_set_color(LANE_COLOUR)
				mesh.surface_add_vertex(tip)
		offset += 4.0
	if light or not give_way_to.is_empty():
		var at := clampf(stop_at(), 0.0, total)
		var here := curve.sample_baked(at)
		var dir := curve.sample_baked(minf(at + 0.5, total)) - curve.sample_baked(maxf(at - 0.5, 0.0))
		dir.y = 0.0
		var side := dir.normalized().cross(Vector3.UP) * 1.6 if dir.length() > 0.001 else Vector3.RIGHT
		mesh.surface_set_color(STOP_COLOUR)
		mesh.surface_add_vertex(here - side + Vector3.UP * 0.1)
		mesh.surface_set_color(STOP_COLOUR)
		mesh.surface_add_vertex(here + side + Vector3.UP * 0.1)
	mesh.surface_end()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.vertex_color_use_as_albedo = true
	mesh.surface_set_material(0, material)
	_preview.mesh = mesh
