@tool
class_name ParkingBay
extends Node3D
## A parking space: a rectangle on the ground, centred on this node, whose -Z axis points into
## the bay from where cars enter it. It draws its own edges, and says which way a parked car must
## face, whether the bay is reserved, and whether something already stands in it. A kerbside
## space for parallel parking is a bay too, laid along the road.

enum Facing {
	EITHER, ## Nose in or reversed in.
	NOSE_IN, ## Facing into the bay (its -Z).
	REVERSED, ## Facing out of the bay, towards where cars enter.
}

## Width across the bay and length into it, in metres.
@export var size := Vector2(2.5, 5.0):
	set(value):
		size = value
		_queue_rebuild()
@export var facing := Facing.EITHER
## A bay drivers may not use here, such as one for permit holders; drawn in yellow.
@export var reserved := false:
	set(value):
		reserved = value
		_queue_rebuild()
## Marks the bay as taken even when nothing physical stands in it.
@export var occupied := false
## Draws the edges: the two sides and the far end. A kerbside bay sets this off.
@export var draw_edges := true:
	set(value):
		draw_edges = value
		_queue_rebuild()

var _edges: Array[RoadMarking] = []
var _rebuild_queued := false


func _ready() -> void:
	_rebuild()


## Whether the bay is free to park in: not marked occupied and nothing on the obstacle layer
## standing in it.
func is_free() -> bool:
	if occupied:
		return false
	var space := get_world_3d().direct_space_state
	var query := PhysicsShapeQueryParameters3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size.x * 0.8, 1.0, size.y * 0.8)
	query.shape = box
	query.transform = Transform3D(global_basis, global_position + Vector3.UP * 0.75)
	query.collision_mask = Layers.OBSTACLE
	return space.intersect_shape(query, 1).is_empty()


## How far, in metres, the furthest of [param points] lies outside the bay; 0 when all are in.
func overhang(points: PackedVector3Array) -> float:
	var worst := 0.0
	for p in points:
		var local := to_local(p)
		worst = maxf(worst, maxf(absf(local.x) - size.x * 0.5, absf(local.z) - size.y * 0.5))
	return worst


func contains(point: Vector3) -> bool:
	return overhang(PackedVector3Array([point])) <= 0.0


## Degrees between a car's forward direction and the way the bay requires it to face.
func facing_error(car_forward: Vector3) -> float:
	var into := -global_basis.z
	into.y = 0.0
	into = into.normalized()
	var fwd := car_forward
	fwd.y = 0.0
	fwd = fwd.normalized()
	var nose_in := rad_to_deg(fwd.angle_to(into))
	var reversed := rad_to_deg(fwd.angle_to(-into))
	match facing:
		Facing.NOSE_IN:
			return nose_in
		Facing.REVERSED:
			return reversed
	return minf(nose_in, reversed)


func _queue_rebuild() -> void:
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	_rebuild.call_deferred()


func _rebuild() -> void:
	_rebuild_queued = false
	for edge in _edges:
		if is_instance_valid(edge):
			edge.queue_free()
	_edges.clear()
	if not draw_edges:
		return
	var hw := size.x * 0.5
	var hl := size.y * 0.5
	var kind := RoadMarking.Kind.NO_PARKING if reserved else RoadMarking.Kind.BAY_EDGE
	for line in [
			[Vector3(-hw, 0, hl), Vector3(-hw, 0, -hl)],
			[Vector3(hw, 0, hl), Vector3(hw, 0, -hl)],
			[Vector3(-hw, 0, -hl), Vector3(hw, 0, -hl)]]:
		var edge := RoadMarking.new()
		edge.kind = kind
		edge.width = 0.1
		edge.curve = Curve3D.new()
		edge.curve.add_point(line[0])
		edge.curve.add_point(line[1])
		add_child(edge, false, INTERNAL_MODE_BACK)
		_edges.append(edge)
