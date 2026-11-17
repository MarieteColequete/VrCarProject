class_name TrafficSnapshot
extends RefCounted
## What road users know of the world in one physics tick, copied on the main thread before they
## think: every road user, vehicle and static obstacle as an oriented box on the ground, bucketed
## in a grid, and every path they drive with its rules already evaluated. It is read-only while road
## users think on worker threads, so thinking touches no node and no physics server, and every road
## user sees the same, last committed tick, whatever order the threads run in.

const CELL := 10.0


## A body on the ground plane: an oriented box with a velocity.
class Box:
	var node: Node3D
	var centre: Vector2
	## Unit vectors along the box's length (its facing) and across it.
	var along: Vector2
	var across: Vector2
	var half_length := 0.0
	var half_width := 0.0
	var velocity := Vector2.ZERO
	## Whether the body is a road user, so queuing behind it is traffic rather than a blockage.
	var road_user := false

	func corners() -> PackedVector2Array:
		var l := along * half_length
		var w := across * half_width
		return PackedVector2Array([centre + l - w, centre + l + w, centre - l + w, centre - l - w])


## A path road users drive, with what its rules say this tick.
class Route:
	var node: Path3D
	var lane: TrafficLane
	var transform: Transform3D
	var inverse: Transform3D
	var curve: Curve3D
	var length := 0.0
	var speed_limit := INF
	var stop_at := INF
	var has_light := false
	## The light shows red, or red and amber; or amber alone.
	var light_red := false
	var light_amber := false
	var has_give_way := false
	## Nothing on the priority lanes is due within the lane's safe gap.
	var way_clear := true
	var crossing_stops := PackedFloat32Array()
	## Whether each crossing in [member crossing_stops] is in use.
	var crossing_busy: Array[bool] = []
	var left: Path3D
	var right: Path3D

	func point_at(offset: float) -> Vector3:
		return transform * curve.sample_baked(clampf(offset, 0.0, length))

	## The distance along the path of its point nearest [param point], and how far off it lies.
	func project(point: Vector3) -> Vector2:
		var local := inverse * point
		var offset := curve.get_closest_offset(local)
		var off := local - curve.sample_baked(offset)
		off.y = 0.0
		return Vector2(offset, off.length())


## The boxes, as flat arrays indexed alike, so threads read plain numbers rather than shared
## objects: per box its node, whether it is a road user, its velocity, its four corners, and its
## centre, axes, and half extents.
var count := 0
var nodes: Array[Node3D] = []
## Each box's node as an instance id, compared without touching the object.
var ids := PackedInt64Array()
var road_user := PackedByteArray()
var velocity := PackedVector2Array()
var corners := PackedVector2Array()
var centre := PackedVector2Array()
var along := PackedVector2Array()
var across := PackedVector2Array()
var half_length := PackedFloat32Array()
var half_width := PackedFloat32Array()
var routes := {}
## Grid cell to the indices of the boxes touching it.
var grid := {}
var _cells := {}


## Adds a body's box and buckets it in every grid cell it touches. Main thread, while building.
func add_box(box: Box) -> void:
	add(box.node, box.centre, box.along, box.half_length, box.half_width, box.velocity,
		box.road_user)


## Adds a box from its parts, without an intermediate [Box]: the form used for every road user
## each tick. [param facing] is the unit facing on the ground.
func add(node: Node3D, at: Vector2, facing: Vector2, half_len: float, half_wid: float,
		moving: Vector2, is_road_user: bool) -> void:
	var index := count
	count += 1
	var side := Vector2(-facing.y, facing.x)
	var l := facing * half_len
	var w := side * half_wid
	nodes.append(node)
	ids.append(node.get_instance_id() if node else 0)
	road_user.append(1 if is_road_user else 0)
	velocity.append(moving)
	corners.append(at + l - w)
	corners.append(at + l + w)
	corners.append(at - l + w)
	corners.append(at - l - w)
	centre.append(at)
	along.append(facing)
	across.append(side)
	half_length.append(half_len)
	half_width.append(half_wid)
	var reach := Vector2.ONE * (half_len + half_wid)
	var c0 := _cell(at - reach)
	var c1 := _cell(at + reach)
	for x in range(c0.x, c1.x + 1):
		for y in range(c0.y, c1.y + 1):
			var key := Vector2i(x, y)
			if not _cells.has(key):
				_cells[key] = PackedInt32Array()
			var bucket: PackedInt32Array = _cells[key]
			bucket.append(index)
			_cells[key] = bucket


## Ends building: the grid becomes readable by threads.
func seal() -> void:
	grid = _cells
	_cells = {}


## The route of [param path], or null when the snapshot does not have it.
func route(path: Path3D) -> Route:
	return routes.get(path)


static func cell_of(p: Vector2) -> Vector2i:
	return _cell(p)


## A box for a node standing at [param transform] with the given size on the ground.
static func box_at(node: Node3D, transform: Transform3D, length: float, width: float,
		velocity: Vector3) -> Box:
	var box := Box.new()
	box.node = node
	box.centre = Vector2(transform.origin.x, transform.origin.z)
	var forward := -transform.basis.z
	box.along = Vector2(forward.x, forward.z).normalized()
	if box.along.is_zero_approx():
		box.along = Vector2(0, -1)
	box.across = Vector2(-box.along.y, box.along.x)
	box.half_length = length * 0.5
	box.half_width = width * 0.5
	box.velocity = Vector2(velocity.x, velocity.z)
	return box


## Copies a path and, for a [TrafficLane], evaluates its rules now. Main thread only.
static func route_of(path: Path3D) -> Route:
	var r := Route.new()
	r.node = path
	r.lane = path as TrafficLane
	r.transform = path.global_transform
	r.inverse = r.transform.affine_inverse()
	r.curve = path.curve
	# Baked here, on the main thread, so sampling from worker threads only reads the cache.
	r.length = path.curve.get_baked_length() if path.curve else 0.0
	var lane := r.lane
	if lane == null:
		return r
	r.speed_limit = lane.speed_limit if lane.speed_limit > 0.0 else INF
	r.stop_at = lane.stop_at()
	r.left = lane.left
	r.right = lane.right
	if lane.light:
		r.has_light = true
		r.light_red = lane.light.is_red()
		r.light_amber = lane.light.state == TrafficLight.Light.AMBER
	r.has_give_way = not lane.give_way_to.is_empty()
	if r.has_give_way:
		r.way_clear = lane.way_is_clear()
	r.crossing_stops = lane.crossing_stops()
	for stop in r.crossing_stops:
		r.crossing_busy.append(lane.crossing_in_use(stop))
	return r


static func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))
