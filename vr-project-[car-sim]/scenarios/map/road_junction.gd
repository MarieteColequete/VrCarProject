@tool
class_name RoadJunction
extends Node3D
## A junction pad where roads meet: a crossroads or a T, its arms pointing north (-Z), east (+X),
## south (+Z), and west (-X), a T having no north arm. The pad is built from the shape in the look
## of Kenney's City Kit (Roads) (see [RoadKit]); a [RoadSegment] joins an arm at
## [method arm_end]. The tool button generates a stop or give way
## line across the incoming half of each controlled arm, and the lanes through the pad, as
## ordinary [RoadMarking] and [TrafficLane] children. The lanes assume one lane each way on every
## arm, on the right of travel, as a [RoadSegment] of the same width lays them; who gives way to
## whom, and lights, are set on the lanes by hand.

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
## A plain material to draw the pad with instead of the kit's look: flat, with no kerbs.
@export var surface: Material:
	set(value):
		surface = value
		_queue_rebuild()
## The speed limit the lanes through the junction get, km/h; 0 for none.
@export var turn_speed_kmh := 30.0
@export_tool_button("Generate lines", "Path3D") var generate_lines_action := generate_lines
@export_tool_button("Generate lanes", "Path3D") var generate_lanes_action := generate_lanes

const DIRECTIONS := [Vector3.FORWARD, Vector3.RIGHT, Vector3.BACK, Vector3.LEFT]
const LIFT := 0.012
const GENERATED := &"road_junction_generated"
const ASPHALT := preload("res://scenarios/kit/asphalt.tres")
const LINES := &"lines"
const LANES := &"lanes"
## Points on each turning lane's curve through the pad.
const TURN_POINTS := 8

var _mesh_instance: MeshInstance3D
var _pavement: StaticBody3D
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
	_clear(LINES)
	var made := make_lines()
	for marking in made:
		_keep(marking)
	return made


## Replaces the generated lanes: from each arm's incoming lane to every other arm's outgoing lane.
func generate_lanes() -> Array[TrafficLane]:
	_clear(LANES)
	var made := make_lanes()
	for lane in made:
		_keep(lane)
	return made


## The lines [method generate_lines] adds, built but not added, so an editor can add them with
## undo.
func make_lines() -> Array[RoadMarking]:
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
		marking.set_meta(GENERATED, LINES)
		made.append(marking)
	return made


## The lanes [method generate_lanes] adds, built but not added: from each arm's end, in on the
## right, through the pad, and out on the right of the other arm, curving for a turn.
func make_lanes() -> Array[TrafficLane]:
	var made: Array[TrafficLane] = []
	var reach := road_width / 2.0 + arm_length
	var offset := road_width / 4.0
	for from in arms():
		var into: Vector3 = -DIRECTIONS[from]
		var entry: Vector3 = DIRECTIONS[from] * reach + into.cross(Vector3.UP) * offset
		for to in arms():
			if to == from:
				continue
			var onward: Vector3 = DIRECTIONS[to]
			var exit: Vector3 = onward * reach + onward.cross(Vector3.UP) * offset
			var lane := TrafficLane.new()
			lane.name = "%sTo%s" % [Arm.keys()[from].capitalize(), Arm.keys()[to].capitalize()]
			lane.curve = _turn(entry, into, exit, onward)
			lane.speed_limit = turn_speed_kmh / 3.6
			lane.set_meta(GENERATED, LANES)
			made.append(lane)
	return made


## The children generated as [param what], [constant LINES] or [constant LANES].
func generated(what: StringName) -> Array[Node]:
	var out: Array[Node] = []
	for child in get_children():
		if child.get_meta(GENERATED, &"") == what:
			out.append(child)
	return out


## A curve from [param entry] heading [param into] to [param exit] heading [param onward]: a
## quadratic bend through where the two headings cross, or straight when they do not.
func _turn(entry: Vector3, into: Vector3, exit: Vector3, onward: Vector3) -> Curve3D:
	var curve := Curve3D.new()
	var inner_a := entry + into * arm_length
	var inner_b := exit - onward * arm_length
	var corner := inner_a.lerp(inner_b, 0.5)
	var cross := into.cross(onward).y
	if absf(cross) > 0.01:
		# Where the line in from inner_a meets the line back from inner_b.
		var t := (inner_b - inner_a).cross(onward).y / cross
		corner = inner_a + into * t
	# Arms of no length start the bend at the arm's end itself.
	var arms_reach := arm_length > 0.01
	if arms_reach:
		curve.add_point(entry)
	for i in TURN_POINTS + 1:
		var s := float(i) / TURN_POINTS
		curve.add_point(inner_a.lerp(corner, s).lerp(corner.lerp(inner_b, s), s))
	if arms_reach:
		curve.add_point(exit)
	return curve


## Adds a generated child the scene saves.
func _keep(node: Node) -> void:
	add_child(node, true)
	node.owner = owner if owner else self


func _clear(what: StringName) -> void:
	for child in generated(what):
		remove_child(child)
		child.free()


func rebuild() -> void:
	_rebuild_queued = false
	if _mesh_instance == null:
		return
	var half := road_width / 2.0
	if surface == null and RoadKit.available():
		var outward: Array = []
		for arm in arms():
			outward.append(DIRECTIONS[arm])
		_mesh_instance.mesh = RoadKit.pad(shape == Shape.T, half, RoadKit.PAVEMENT, outward,
			arm_length)
		_set_pavement(RoadKit.pavement_body(RoadKit.pad_shapes(shape == Shape.T, half,
			RoadKit.PAVEMENT, outward, arm_length)))
		return
	_set_pavement(null)
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
	mesh.surface_set_material(0, surface if surface else ASPHALT)
	_mesh_instance.mesh = mesh


## The pavements' body, which stops the car's tyres at the kerbs; null in a plain surface.
func pavement_body() -> StaticBody3D:
	return _pavement


func _set_pavement(body: StaticBody3D) -> void:
	if _pavement and is_instance_valid(_pavement):
		remove_child(_pavement)
		_pavement.queue_free()
	_pavement = body
	if body:
		add_child(body, false, INTERNAL_MODE_BACK)


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
