class_name LaneData
extends RefCounted
## One path road users follow, as data: a [TrafficLane] with its rules, or a plain [Path3D] such
## as a pedestrian's walk. Baked once when a scenario loads and never changed, so worker threads
## read it freely; its curve is baked on the main thread before any thread samples it.

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


func point_at(offset: float) -> Vector3:
	return transform * curve.sample_baked(clampf(offset, 0.0, length))


## The distance along the lane of its point nearest [param point], and how far off it lies.
func project(point: Vector3) -> Vector2:
	var local := inverse * point
	var offset := curve.get_closest_offset(local)
	var off := local - curve.sample_baked(offset)
	off.y = 0.0
	return Vector2(offset, off.length())


## The lane's direction at [param offset], on the ground, normalised.
func tangent_at(offset: float) -> Vector3:
	var t := point_at(offset + 0.5) - point_at(offset - 0.5)
	t.y = 0.0
	return t.normalized() if t.length() > 0.001 else Vector3.FORWARD


func has_rules() -> bool:
	return is_lane and (light != 0 or not give_way_to.is_empty() or not crossings.is_empty())
