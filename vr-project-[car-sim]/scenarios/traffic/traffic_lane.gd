@tool
class_name TrafficLane
extends Path3D
## One lane of the road network, its curve along the lane's centre in the direction of traffic,
## and the rules road users on it obey. A [ScriptedAgent] whose path is a lane keeps to its speed
## limit, continues onto one of its [member next] lanes at its end, stops at [member stop_offset]
## while its [member light] says so or while traffic on the lanes it gives way to is coming, and
## waits before any of its [member crossings] in use. Lanes are authored in the scene; the agent's
## sensor still reacts to whatever else is in the way.
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
## Pedestrian crossings on the lane, their [CrossingCheck]s; traffic waits before one in use.
## Typed as plain nodes so the lane, its road users, and the crossing check do not load in a
## cycle.
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


## The distance along the lane of its point nearest [param point], and how far off the lane
## [param point] lies, both in metres.
func project(point: Vector3) -> Vector2:
	var local := to_local(point)
	var offset := curve.get_closest_offset(local)
	var off := local - curve.sample_baked(offset)
	off.y = 0.0
	return Vector2(offset, off.length())


## The distances along the lane at which traffic waits before each crossing.
func crossing_stops() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for crossing in crossings:
		var zone := crossing.get(&"crossing_zone") as TriggerZone if crossing else null
		if zone:
			var centre := project(zone.global_position).x
			out.append(maxf(centre - _half_depth(zone) - 1.0, 0.0))
	return out


## Whether the crossing at [param stop], one of [method crossing_stops], is in use.
func crossing_in_use(stop: float) -> bool:
	var index := crossing_stops().find(stop)
	return index >= 0 and crossings[index].call(&"is_in_use")


## Whether pulling out at the stop line is safe now: nothing on the priority lanes is due at the
## meeting point within [member safe_gap] seconds, counting road users on those lanes and any
## vehicle on them, such as the player's car.
func way_is_clear() -> bool:
	if give_way_to.is_empty():
		return true
	var meeting := point_at(stop_at())
	for lane in give_way_to:
		if lane == null:
			continue
		var at := lane.project(meeting).x
		# Road users are read through their public members rather than their class, so the lane
		# and the road user do not load each other in a cycle.
		for user: Node3D in get_tree().get_nodes_in_group(Layers.GROUP_ROAD_USER):
			if user.get(&"path") != lane:
				continue
			# A road user counts until its whole body has cleared the meeting point.
			var length: float = user.get(&"body_size").z
			var clearing := absf(lane.project(user.global_position).x - at) < length
			if clearing or float(user.call(&"time_to", at)) < safe_gap:
				return false
		for node in get_tree().get_nodes_in_group(Layers.GROUP_VEHICLE):
			var probe := node as VehicleProbe
			if probe and lane.vehicle_due(probe, at) < safe_gap:
				return false
	return true


## Seconds until a vehicle on this lane reaches [param offset] along it; 0 when it is there, INF
## when it is not on the lane or already past.
func vehicle_due(probe: VehicleProbe, offset: float) -> float:
	var where := project(probe.global_position)
	if where.y > 2.5:
		return INF
	var remaining := offset - where.x
	if absf(remaining) <= probe.body_length:
		return 0.0
	if remaining < 0.0:
		return INF
	return remaining / maxf(probe.velocity.length(), 0.5)


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if curve == null or curve.point_count < 2:
		warnings.append("Draw the lane's curve in the direction of traffic.")
	for crossing in crossings:
		if crossing == null or not crossing.has_method(&"is_in_use"):
			warnings.append("Crossings must be CrossingCheck nodes.")
			break
	return warnings


static func _half_depth(zone: TriggerZone) -> float:
	for child in zone.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D:
			return maxf(child.shape.size.x, child.shape.size.z) * 0.5
	return 1.0


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
