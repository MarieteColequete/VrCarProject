@tool
class_name RoadSegment
extends Path3D
## A stretch of road along its curve, the curve on the road's centre line: the road is built from
## the curve in the look of Kenney's City Kit (Roads) (see [RoadKit]), and the tool buttons
## generate the road's [TrafficLane]s and [RoadMarking]s as ordinary children, which are saved with
## the map and can be edited like any other. Traffic keeps to the right: the lanes running in the
## curve's direction lie on its right-hand side. Generating again replaces what the segment
## generated before, and leaves other children alone.

enum Centre { DASHED, SOLID, DOUBLE_SOLID, NONE }

## Lanes in each direction, or in all for a one-way road.
@export_range(1, 4) var lanes_each_way := 1:
	set(value):
		lanes_each_way = value
		_queue_rebuild()
@export var lane_width := 3.5:
	set(value):
		lane_width = value
		_queue_rebuild()
## All lanes run in the curve's direction.
@export var one_way := false:
	set(value):
		one_way = value
		_queue_rebuild()
## The speed limit the generated lanes get, km/h; 0 for none.
@export var speed_limit_kmh := 50.0
## The line between the two directions.
@export var centre := Centre.DASHED
## Kerbs along both edges, with a pavement beyond.
@export var kerbs := true:
	set(value):
		kerbs = value
		_queue_rebuild()
## The pavement's width beyond each kerb, metres.
@export_range(0.5, 6.0, 0.1) var pavement := RoadKit.PAVEMENT:
	set(value):
		pavement = value
		_queue_rebuild()
## A plain material to draw the road with instead of the kit's look: a flat strip, kerbs and
## pavement left to the markings.
@export var surface: Material:
	set(value):
		surface = value
		_queue_rebuild()
@export_tool_button("Generate lanes", "Path3D") var generate_lanes_action := generate_lanes
@export_tool_button("Generate markings", "Path3D") var generate_markings_action := generate_markings

## Metres between the points of generated curves.
const STEP := 2.0
## Height of the asphalt above the ground.
const LIFT := 0.01
const GENERATED := &"road_segment_generated"
const ASPHALT := preload("res://scenarios/kit/asphalt.tres")
const LANES := &"lanes"
const MARKINGS := &"markings"

var _mesh_instance: MeshInstance3D
var _pavement: StaticBody3D
var _asphalt: StaticBody3D
var _rebuild_queued := false


func _ready() -> void:
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance, false, INTERNAL_MODE_BACK)
	if not curve_changed.is_connected(_queue_rebuild):
		curve_changed.connect(_queue_rebuild)
	rebuild()


## The road's full width, metres.
func width() -> float:
	return lanes_each_way * lane_width * (1.0 if one_way else 2.0)


## The offsets of the lane centres from the centre line, to the right of the curve's direction;
## [param forward] for the lanes running with the curve.
func lane_offsets(forward: bool) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if one_way and not forward:
		return out
	for i in lanes_each_way:
		if one_way:
			out.append((i - (lanes_each_way - 1) / 2.0) * lane_width)
		else:
			out.append((i + 0.5) * lane_width * (1.0 if forward else -1.0))
	return out


## Replaces the generated lanes: one [TrafficLane] per lane, in its direction of travel, with the
## speed limit and the lanes beside it set.
func generate_lanes() -> Array[TrafficLane]:
	_clear(LANES)
	var made := make_lanes()
	for lane in made:
		_keep(lane)
	return made


## Replaces the generated markings: the kerbs, the centre line, and dashed lines between lanes
## running the same way.
func generate_markings() -> Array[RoadMarking]:
	_clear(MARKINGS)
	var made := make_markings()
	for marking in made:
		_keep(marking)
	return made


## The lanes [method generate_lanes] adds, built but not added, so an editor can add them with
## undo.
func make_lanes() -> Array[TrafficLane]:
	var made: Array[TrafficLane] = []
	for forward in [true, false]:
		var lanes: Array[TrafficLane] = []
		for offset in lane_offsets(forward):
			var lane := TrafficLane.new()
			lane.name = "%s%d" % ["Lane" if forward else "LaneBack", lanes.size() + 1]
			lane.curve = _offset_curve(offset, not forward)
			lane.speed_limit = speed_limit_kmh / 3.6
			lane.set_meta(GENERATED, LANES)
			lanes.append(lane)
		for i in lanes.size():
			if i > 0:
				lanes[i].left = lanes[i - 1]
			if i + 1 < lanes.size():
				lanes[i].right = lanes[i + 1]
		made.append_array(lanes)
	return made


## The markings [method generate_markings] adds, built but not added.
func make_markings() -> Array[RoadMarking]:
	var made: Array[RoadMarking] = []
	var half := width() / 2.0
	if kerbs:
		made.append(_marking("KerbRight", RoadMarking.Kind.KERB, half))
		made.append(_marking("KerbLeft", RoadMarking.Kind.KERB, -half))
	if not one_way and centre != Centre.NONE:
		var kinds := {Centre.DASHED: RoadMarking.Kind.DASHED, Centre.SOLID: RoadMarking.Kind.SOLID,
			Centre.DOUBLE_SOLID: RoadMarking.Kind.DOUBLE_SOLID}
		made.append(_marking("CentreLine", kinds[centre], 0.0))
	for i in range(1, lanes_each_way):
		if one_way:
			made.append(_marking("LaneLine%d" % i, RoadMarking.Kind.DASHED,
				-half + i * lane_width))
		else:
			made.append(_marking("LaneLine%d" % i, RoadMarking.Kind.DASHED, i * lane_width))
			made.append(_marking("LaneLineBack%d" % i, RoadMarking.Kind.DASHED, -i * lane_width))
	return made


## Points along the curve, local space, with the horizontal direction to their right and the
## road's up, square to the right and to the curve's slope: [code][position, right, up][/code]
## every [constant STEP] metres and at the end. The right stays level, so a road climbs and falls
## with its curve's height but never banks.
func frames() -> Array:
	var out: Array = []
	if curve == null or curve.point_count < 2:
		return out
	var total := curve.get_baked_length()
	if total <= 0.0:
		return out
	var offsets: Array[float] = []
	var at := 0.0
	while at < total - STEP * 0.25:
		offsets.append(at)
		at += STEP
	offsets.append(total)
	for offset in offsets:
		var ahead := curve.sample_baked(minf(offset + 0.25, total))
		var behind := curve.sample_baked(maxf(offset - 0.25, 0.0))
		var dir := ahead - behind
		var flat := Vector3(dir.x, 0.0, dir.z)
		var right := flat.normalized().cross(Vector3.UP) if flat.length() > 0.0001 \
			else Vector3.RIGHT
		var up := right.cross(dir).normalized() if flat.length() > 0.0001 else Vector3.UP
		out.append([curve.sample_baked(offset), right, up])
	return out


func rebuild() -> void:
	_rebuild_queued = false
	if _mesh_instance == null:
		return
	_mesh_instance.mesh = _build_mesh()
	_asphalt = _swap_body(_asphalt, RoadKit.surface_body(RoadKit.surface_shapes(frames(),
		width() / 2.0)))
	_set_pavement(RoadKit.pavement_body(RoadKit.pavement_shapes(frames(), width() / 2.0, pavement))
		if kit_look() and kerbs else null)
	for marking in generated(MARKINGS):
		if marking is RoadMarking and marking.kind == RoadMarking.Kind.KERB:
			marking.paint = not kit_look()
	Terrain.notify_changed(self)


## The pavements' body, which stops the car's tyres at the kerbs; null without kerbs or in a
## plain surface.
func pavement_body() -> StaticBody3D:
	return _pavement


## The asphalt's body, of the asphalt [BodyType], whose top is the drawn road; null without a
## curve.
func surface_body() -> StaticBody3D:
	return _asphalt


func _set_pavement(body: StaticBody3D) -> void:
	_pavement = _swap_body(_pavement, body)


## Replaces the internal body [param old] with [param body], returning it.
func _swap_body(old: StaticBody3D, body: StaticBody3D) -> StaticBody3D:
	if old and is_instance_valid(old):
		remove_child(old)
		old.queue_free()
	if body:
		add_child(body, false, INTERNAL_MODE_BACK)
	return body


## Whether the road is drawn in the kit's look, kerbs and pavement included.
func kit_look() -> bool:
	return surface == null and RoadKit.available()


func _queue_rebuild() -> void:
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	rebuild.call_deferred()


func _build_mesh() -> ArrayMesh:
	var along := frames()
	if along.size() < 2:
		return null
	if kit_look():
		return RoadKit.road(along, width() / 2.0, pavement, kerbs)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := width() / 2.0
	var travelled := 0.0
	for i in along.size() - 1:
		var a: Array = along[i]
		var b: Array = along[i + 1]
		var step: float = (b[0] - a[0]).length()
		var quad := [a[0] - a[1] * half, a[0] + a[1] * half,
			b[0] + b[1] * half, b[0] - b[1] * half]
		var ups := [a[2], a[2], b[2], b[2]]
		var uvs := [Vector2(0, travelled), Vector2(1, travelled), Vector2(1, travelled + step),
			Vector2(0, travelled + step)]
		for k in [0, 2, 1, 0, 3, 2]:
			st.set_normal(ups[k])
			st.set_uv(uvs[k] / maxf(width(), 0.01))
			st.add_vertex(quad[k] + ups[k] * LIFT)
		travelled += step
	var mesh := st.commit()
	mesh.surface_set_material(0, surface if surface else ASPHALT)
	return mesh


func _offset_curve(offset: float, reverse: bool) -> Curve3D:
	var points := PackedVector3Array()
	for frame: Array in frames():
		points.append(frame[0] + frame[1] * offset)
	if reverse:
		points.reverse()
	var out := Curve3D.new()
	for point in points:
		out.add_point(point)
	return out


func _marking(marking_name: String, kind: RoadMarking.Kind, offset: float) -> RoadMarking:
	var marking := RoadMarking.new()
	marking.name = marking_name
	marking.kind = kind
	marking.curve = _offset_curve(offset, false)
	marking.paint = kind != RoadMarking.Kind.KERB or not kit_look()
	marking.set_meta(GENERATED, MARKINGS)
	return marking


## The children generated as [param what], [constant LANES] or [constant MARKINGS].
func generated(what: StringName) -> Array[Node]:
	var out: Array[Node] = []
	for child in get_children():
		if child.get_meta(GENERATED, &"") == what:
			out.append(child)
	return out


## Where the road starts and ends, local space, each facing out of the road along -Z: where
## another road or a junction arm joins it. Empty without a curve.
func ends() -> Array[Transform3D]:
	var along := frames()
	if along.size() < 2:
		return []
	var first: Array = along[0]
	var last: Array = along[-1]
	var out: Array[Transform3D] = []
	out.append(Transform3D(Basis.looking_at(-_ahead(first[1])), first[0]))
	out.append(Transform3D(Basis.looking_at(_ahead(last[1])), last[0]))
	return out


## The direction of travel along the curve where [param right] is to its right.
static func _ahead(right: Vector3) -> Vector3:
	return Vector3.UP.cross(right).normalized()


## Adds a generated child the scene saves.
func _keep(node: Node) -> void:
	add_child(node, true)
	node.owner = owner if owner else self


func _clear(what: StringName) -> void:
	for child in generated(what):
		remove_child(child)
		child.free()
