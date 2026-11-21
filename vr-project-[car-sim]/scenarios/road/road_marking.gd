@tool
class_name RoadMarking
extends Path3D
## A road marking drawn along its curve: a centre or lane line, a stop or give way line, a zebra,
## a bay edge, a no-parking line, or a kerb. A drawn kerb is also solid: a thin wall of the
## pavement [BodyType] along it stops the car's tyres. The same curve draws the paint and feeds
## detection, through the scenario's [MarkingIndex], so what the driver sees is what is judged. A dashed line
## is judged along its whole length, gaps included: crossing it in a gap is still crossing it.

enum Kind { SOLID, DASHED, DOUBLE_SOLID, STOP_LINE, GIVE_WAY_LINE, ZEBRA, BAY_EDGE, NO_PARKING, KERB }

@export var kind := Kind.SOLID:
	set(value):
		kind = value
		_queue_rebuild()
## Width of the paint, in metres; for a zebra, the width of the crossing.
@export var width := 0.12:
	set(value):
		width = value
		_queue_rebuild()
## Painted and unpainted lengths of a dashed line or a zebra.
@export var dash_length := 3.0:
	set(value):
		dash_length = value
		_queue_rebuild()
@export var gap_length := 6.0:
	set(value):
		gap_length = value
		_queue_rebuild()
## Whether it is drawn. A kerb along a road of the kit is judged but not drawn: the road draws
## the kerb itself, and its pavement is solid.
@export var paint := true:
	set(value):
		paint = value
		_queue_rebuild()

const PAINT_HEIGHT := 0.025
const KERB_HEIGHT := 0.15
const WHITE := Color(0.95, 0.95, 0.95)
const YELLOW := Color(0.95, 0.8, 0.1)
const KERB_GREY := Color(0.6, 0.6, 0.6)
## Thickness of a drawn kerb's wall, centred on the line, so a tyre stopped by it is still on the
## kerb line as [LineCheck] judges it.
const KERB_WALL := 0.06

var _mesh_instance: MeshInstance3D
var _wall: StaticBody3D
var _rebuild_queued := false


func _ready() -> void:
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance, false, INTERNAL_MODE_BACK)
	if not curve_changed.is_connected(_queue_rebuild):
		curve_changed.connect(_queue_rebuild)
	rebuild()


## Half the width detection treats as on the marking, in metres.
func half_width() -> float:
	return width * 1.5 if kind == Kind.DOUBLE_SOLID else width * 0.5


## Whether the marking separates lanes (solid, dashed, or double solid), the lines crossed in a
## lane change.
func is_lane_line() -> bool:
	return is_lane_kind(kind)


## Whether a marking of [param marking_kind] separates lanes.
static func is_lane_kind(marking_kind: int) -> bool:
	return marking_kind == Kind.SOLID or marking_kind == Kind.DASHED \
		or marking_kind == Kind.DOUBLE_SOLID


## The marking's centreline in world space, along the baked curve.
func world_points() -> PackedVector3Array:
	var out := PackedVector3Array()
	if curve == null:
		return out
	for p in curve.get_baked_points():
		out.append(global_transform * p)
	return out


func rebuild() -> void:
	_rebuild_queued = false
	if _mesh_instance == null:
		return
	_mesh_instance.mesh = _build_mesh()
	if _wall and is_instance_valid(_wall):
		remove_child(_wall)
		_wall.queue_free()
	_wall = RoadKit.pavement_body(_wall_shapes()) if kind == Kind.KERB and paint else null
	if _wall:
		add_child(_wall, false, INTERNAL_MODE_BACK)


## The wall a drawn kerb stands up as; null for any other marking.
func wall() -> StaticBody3D:
	return _wall


func _wall_shapes() -> Array[Shape3D]:
	var out: Array[Shape3D] = []
	if curve == null or curve.point_count < 2:
		return out
	var points := curve.tessellate(4, 4.0)
	var half := KERB_WALL / 2.0
	for i in points.size() - 1:
		var along := points[i + 1] - points[i]
		along.y = 0.0
		if along.length() < 0.001:
			continue
		var right := along.normalized().cross(Vector3.UP) * half
		out.append(RoadKit.prism([points[i] - right, points[i] + right, points[i + 1] + right,
			points[i + 1] - right]))
	return out


func _queue_rebuild() -> void:
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	rebuild.call_deferred()


func _build_mesh() -> ArrayMesh:
	if not paint or curve == null or curve.get_baked_points().size() < 2:
		return null
	var points := curve.get_baked_points()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var height := KERB_HEIGHT if kind == Kind.KERB else PAINT_HEIGHT
	var dashed := kind == Kind.DASHED or kind == Kind.ZEBRA
	if kind == Kind.DOUBLE_SOLID:
		_add_strip(st, points, -width, width, height, false)
		_add_strip(st, points, width, width, height, false)
	else:
		_add_strip(st, points, 0.0, width, height, dashed)
	var material := StandardMaterial3D.new()
	material.albedo_color = _colour()
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	st.set_material(material)
	st.generate_normals()
	return st.commit()


func _colour() -> Color:
	match kind:
		Kind.NO_PARKING:
			return YELLOW
		Kind.KERB:
			return KERB_GREY
	return WHITE


## Adds a flat strip along the points, its centre [param offset] metres to the right.
func _add_strip(st: SurfaceTool, points: PackedVector3Array, offset: float, strip_width: float,
		height: float, dashed: bool) -> void:
	var travelled := 0.0
	var period := dash_length + gap_length
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var length := a.distance_to(b)
		var mid := travelled + length * 0.5
		travelled += length
		if dashed and period > 0.0 and fmod(mid, period) >= dash_length:
			continue
		var along := (b - a).normalized()
		var right := along.cross(Vector3.UP).normalized()
		var lift := Vector3(0.0, height, 0.0)
		var l := right * (offset - strip_width * 0.5)
		var r := right * (offset + strip_width * 0.5)
		var quad := [a + l + lift, a + r + lift, b + r + lift, b + l + lift]
		for index in [0, 2, 1, 0, 3, 2]:
			st.add_vertex(quad[index])
