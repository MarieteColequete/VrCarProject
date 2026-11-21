@tool
class_name RoadJunction
extends Node3D
## A junction pad where roads meet: a crossroads or a T, its arms pointing north (-Z), east (+X),
## south (+Z), and west (-X), a T having no north arm. The asphalt is built from the shape; a
## [RoadSegment] joins an arm at [method arm_end]. The tool button generates a stop or give way
## line across the incoming half of each controlled arm, as ordinary [RoadMarking] children.

enum Shape { CROSSROADS, T }
enum Arm { NORTH, EAST, SOUTH, WEST }
enum Line { GIVE_WAY, STOP }

@export var shape := Shape.CROSSROADS:
	set(value):
		shape = value
		_queue_rebuild()
## Width of the roads that meet, metres.
@export var road_width := 7.0:
	set(value):
		road_width = value
		_queue_rebuild()
## How far each arm reaches beyond the central square, metres.
@export var arm_length := 4.0:
	set(value):
		arm_length = value
		_queue_rebuild()
## The arms traffic must give way or stop on.
@export_flags("North", "East", "South", "West") var controlled_arms := 0
@export var line := Line.GIVE_WAY
@export var surface: Material = preload("res://scenarios/kit/asphalt.tres"):
	set(value):
		surface = value
		_queue_rebuild()
@export_tool_button("Generate lines", "Path3D") var generate_lines_action := generate_lines

const DIRECTIONS := [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]
const LIFT := 0.012
const GENERATED := &"road_junction_generated"

var _mesh_instance: MeshInstance3D
var _rebuild_queued := false


func _ready() -> void:
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance, false, INTERNAL_MODE_BACK)
	rebuild()


## The junction's arms.
func arms() -> Array[Arm]:
	var out: Array[Arm] = [Arm.EAST, Arm.SOUTH, Arm.WEST]
	if shape == Shape.CROSSROADS:
		out.push_front(Arm.NORTH)
	return out


## Where [param arm] ends, local space, facing out of the junction along -Z: the start of a road
## leaving by that arm.
func arm_end(arm: Arm) -> Transform3D:
	var out: Vector3 = DIRECTIONS[arm]
	return Transform3D(Basis.looking_at(out), out * (road_width / 2.0 + arm_length))


## Replaces the generated lines: one across the incoming half of each controlled arm.
func generate_lines() -> Array[RoadMarking]:
	for child in get_children():
		if child.has_meta(GENERATED):
			remove_child(child)
			child.free()
	var made: Array[RoadMarking] = []
	var half := road_width / 2.0
	for arm in arms():
		if not controlled_arms & (1 << arm):
			continue
		var out: Vector3 = DIRECTIONS[arm]
		var right := (-out).cross(Vector3.UP)
		var start := out * (half + 0.3)
		var marking := RoadMarking.new()
		marking.name = "%sLine" % Arm.keys()[arm].capitalize()
		marking.kind = RoadMarking.Kind.STOP_LINE if line == Line.STOP \
			else RoadMarking.Kind.GIVE_WAY_LINE
		marking.width = 0.3
		marking.curve = Curve3D.new()
		marking.curve.add_point(start)
		marking.curve.add_point(start + right * half)
		marking.set_meta(GENERATED, true)
		add_child(marking, true)
		marking.owner = owner if owner else self
		made.append(marking)
	return made


func rebuild() -> void:
	_rebuild_queued = false
	if _mesh_instance == null:
		return
	var half := road_width / 2.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(st, Vector3(-half, 0, -half), Vector3(half, 0, half))
	for arm in arms():
		var out: Vector3 = DIRECTIONS[arm]
		var side := out.cross(Vector3.UP).abs() * half
		var near := out * half
		var far := out * (half + arm_length)
		_quad(st, (near - side).min(far + side), (near - side).max(far + side))
	var mesh := st.commit()
	if surface:
		mesh.surface_set_material(0, surface)
	_mesh_instance.mesh = mesh


func _queue_rebuild() -> void:
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	rebuild.call_deferred()


func _quad(st: SurfaceTool, low: Vector3, high: Vector3) -> void:
	var corners := [Vector3(low.x, LIFT, low.z), Vector3(high.x, LIFT, low.z),
		Vector3(high.x, LIFT, high.z), Vector3(low.x, LIFT, high.z)]
	for k in [0, 1, 2, 0, 2, 3]:
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(corners[k].x, corners[k].z) / maxf(road_width, 0.01))
		st.add_vertex(corners[k])
