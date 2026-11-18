class_name TrafficSnapshot
extends RefCounted
## What road users know of the world in one tick, copied on the main thread before they think:
## every road user, the player's car, and every obstacle as an oriented box on the ground, bucketed
## in a grid, and every lane they drive with its rules already evaluated. It is read-only while
## road users think on worker threads, so thinking touches no node and no world, and every road
## user sees the same tick, whatever order the threads run in.

const CELL := 10.0


## A lane with what its rules say this tick, its values copied from its [LaneData] so thinking
## reads one object per lane rather than two. Road users on the lane still share it, and reading
## its members from threads goes through the engine's object validation.
class Route:
	var lane_id := 0
	var is_lane := false
	var curve: Curve3D
	var transform := Transform3D()
	var inverse := Transform3D()
	var length := 0.0
	var speed_limit := INF
	var stop_at := INF
	var left := 0
	var right := 0
	## Where traffic waits before each of the lane's crossings, and whether each is in use.
	var crossing_stops := PackedFloat32Array()
	var crossing_busy: Array[bool] = []
	var has_light := false
	## The light shows red, or red and amber; or amber alone.
	var light_red := false
	var light_amber := false
	var has_give_way := false
	## Nothing on the priority lanes is due within the lane's safe gap.
	var way_clear := true

	static func of(lane: LaneData) -> Route:
		var r := Route.new()
		r.lane_id = lane.id
		r.is_lane = lane.is_lane
		r.curve = lane.curve
		r.transform = lane.transform
		r.inverse = lane.inverse
		r.length = lane.length
		r.speed_limit = lane.speed_limit
		r.stop_at = lane.stop_at
		r.left = lane.left
		r.right = lane.right
		for crossing in lane.crossings:
			r.crossing_stops.append(crossing.stop)
		return r

	func point_at(offset: float) -> Vector3:
		return transform * curve.sample_baked(clampf(offset, 0.0, length))

	## The distance along the lane of its point nearest [param point], and how far off it lies.
	func project(point: Vector3) -> Vector2:
		var local := inverse * point
		var offset := curve.get_closest_offset(local)
		var off := local - curve.sample_baked(offset)
		off.y = 0.0
		return Vector2(offset, off.length())


## The boxes, as flat arrays indexed alike, so threads read plain numbers rather than shared
## objects: per box its entity, whether it is a road user, its velocity, its four corners, and its
## centre, axes, and half extents.
var count := 0
var ids := PackedInt64Array()
var road_user := PackedByteArray()
var velocity := PackedVector2Array()
var corners := PackedVector2Array()
var centre := PackedVector2Array()
var along := PackedVector2Array()
var across := PackedVector2Array()
var half_length := PackedFloat32Array()
var half_width := PackedFloat32Array()
## Lane entity to its [Route].
var routes := {}
## Grid cell to the indices of the boxes touching it.
var grid := {}
var _cells := {}


## Adds a box: [param facing] is the unit facing on the ground. Main thread, while building.
func add(id: int, at: Vector2, facing: Vector2, half_len: float, half_wid: float,
		moving: Vector2, is_road_user: bool) -> void:
	var index := count
	count += 1
	var side := Vector2(-facing.y, facing.x)
	var l := facing * half_len
	var w := side * half_wid
	ids.append(id)
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
	var c0 := cell_of(at - reach)
	var c1 := cell_of(at + reach)
	for x in range(c0.x, c1.x + 1):
		for y in range(c0.y, c1.y + 1):
			var key := Vector2i(x, y)
			if not _cells.has(key):
				_cells[key] = PackedInt32Array()
			_cells[key].append(index)


## Adds the box at [param box] (its centre transform) with full [param size].
func add_box(id: int, box: Transform3D, size: Vector3, moving: Vector3, is_road_user: bool) -> void:
	var g := Geo.ground_box(box, size * 0.5)
	add(id, g[0], g[1], g[2], g[3], Vector2(moving.x, moving.z), is_road_user)


## Ends building: the grid becomes readable by threads.
func seal() -> void:
	grid = _cells
	_cells = {}


## The route of lane [param lane], or null when the snapshot does not have it.
func route(lane: int) -> Route:
	return routes.get(lane)


static func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))
