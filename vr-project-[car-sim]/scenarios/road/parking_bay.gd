@tool
class_name ParkingBay
extends Node3D
## A parking space: a rectangle on the ground, centred on this node, whose -Z axis points into
## the bay from where cars enter it. It draws its own edges, and says which way a parked car must
## face, and whether the bay is reserved or taken. A kerbside space for parallel parking is a bay
## too, laid along the road. A [Bake] turns it into a bay entity for the parking rules.

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
## Marks the bay as taken even when nothing stands in it.
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
