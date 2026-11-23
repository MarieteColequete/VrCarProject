class_name LaneData
extends RefCounted
## One path road users follow, as data: a [TrafficLane] with its rules, or a plain [Path3D] such
## as a pedestrian's walk. Baked once when a scenario loads and never changed. Read on the main
## thread: road users thinking on worker threads read lanes through the [RouteTable]'s columns.

var id := 0
var name: StringName
## False for a plain path, which has no rules, neighbours, or next lanes.
var is_lane := false
var curve: Curve3D
var transform := Transform3D()
var inverse := Transform3D()
var length := 0.0
## Metres per second; INF for none.
var speed_limit := INF
## Metres along the lane of the stop line for the light and for giving way.
var stop_at := INF
## The light entity at the stop line, or 0.
var light := 0
## The lanes with priority at the stop line.
var give_way_to := PackedInt64Array()
var safe_gap := 4.0
## Pedestrian crossings on the lane: each [code]{zone, transform, half, pedestrians, margin,
## stop}[/code], where stop is where traffic waits before it.
var crossings: Array[Dictionary] = []
var next := PackedInt64Array()
var left := 0
var right := 0


## A lane [param id] along [param curve] placed at [param p_transform], with [param settings]
## for its other fields (such as [code]is_lane[/code] or [code]speed_limit[/code]). The curve is
## baked here, once, so sampling it only reads the cache.
static func of(id: int, curve: Curve3D, p_transform := Transform3D(),
		settings := {}) -> LaneData:
	var lane := LaneData.new()
	lane.id = id
	lane.curve = curve
	lane.transform = p_transform
	lane.inverse = p_transform.affine_inverse()
	lane.length = curve.get_baked_length()
	for key: StringName in settings:
		lane.set(key, settings[key])
	return lane


func point_at(offset: float) -> Vector3:
	return transform * curve.sample_baked(clampf(offset, 0.0, length))


## Which way the lane runs on the ground at [param offset]: from half a metre behind to half a
## metre ahead, level, not normalised (nought where the lane is shorter than that).
func ground_tangent(offset: float) -> Vector3:
	var along := point_at(offset + 0.5) - point_at(offset - 0.5)
	along.y = 0.0
	return along


## The distance along the lane of its point nearest [param point], and how far off it lies.
func project(point: Vector3) -> Vector2:
	var local := inverse * point
	var offset := curve.get_closest_offset(local)
	var off := local - curve.sample_baked(offset)
	off.y = 0.0
	return Vector2(offset, off.length())

