class_name GpsMap
extends RefCounted
## What the dashboard's GPS draws ([CarTablet]), flat on the ground's x and z, in metres, read once
## when a scenario loads ([GpsReader]): the roads' faces, with the grass islands that stand on them
## (a roundabout's centre); the lines painted on them; the ways the scenario wants the car to go
## ([GpsRoute]); and the goals that end its steps or the attempt. The rest is plain geometry: where
## a point is on the heading-up screen ([method heading_up]) and how far the car still has to go
## along a way ([method along]).

## The roads' faces, three points to a triangle, and the islands' after them.
var roads := PackedVector2Array()
var islands := PackedVector2Array()
## The painted lines, each a polyline.
var lines: Array[PackedVector2Array] = []
## The ways: [code]{step, points}[/code] each, the step's index or -1 for the whole attempt.
var routes: Array[Dictionary] = []
## The goals: [code]{step, centre, radius}[/code] each, the step's index or -1 for the attempt.
var goals: Array[Dictionary] = []


## [param points] flat on the ground: their x and z.
static func flat(points: PackedVector3Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	out.resize(points.size())
	for i in points.size():
		out[i] = Vector2(points[i].x, points[i].z)
	return out


## The way for step [param step]: its own, or else the whole attempt's; empty for none.
func route_for(step: int) -> PackedVector2Array:
	return _for(routes, step, &"points", PackedVector2Array())


## The goal for step [param step], [code]{step, centre, radius}[/code]: its own, or else the
## attempt's; empty for none.
func goal_for(step: int) -> Dictionary:
	for goal in goals:
		if goal.step == step:
			return goal
	for goal in goals:
		if goal.step == -1:
			return goal
	return {}


## From the ground (x and z) to the screen, heading up: the car at [param car] sits on
## [param anchor] facing up the screen along [param forward] (on the ground), [param scale] pixels
## to the metre.
static func heading_up(car: Vector2, forward: Vector2, scale: float, anchor: Vector2) -> Transform2D:
	var f := forward.normalized() if forward.length_squared() > 1e-6 else Vector2(0.0, -1.0)
	# The car's right on the ground is (-f.y, f.x); right goes right on the screen, ahead goes up.
	var x_axis := Vector2(-f.y, -f.x) * scale
	var y_axis := Vector2(f.x, -f.y) * scale
	return Transform2D(x_axis, y_axis, anchor - x_axis * car.x - y_axis * car.y)


## Where [param at] is along the way [param points]: [code]{left, index, point}[/code], the metres
## left from its nearest point to the end, the segment it lies on, and that nearest point.
static func along(points: PackedVector2Array, at: Vector2) -> Dictionary:
	if points.size() < 2:
		return {left = 0.0, index = 0, point = points[0] if points.size() == 1 else at}
	var best := INF
	var index := 0
	var point := points[0]
	for i in points.size() - 1:
		var near := Geometry2D.get_closest_point_to_segment(at, points[i], points[i + 1])
		var d := near.distance_squared_to(at)
		if d < best:
			best = d
			index = i
			point = near
	var left := point.distance_to(points[index + 1])
	for i in range(index + 1, points.size() - 1):
		left += points[i].distance_to(points[i + 1])
	return {left = left, index = index, point = point}


func _for(list: Array[Dictionary], step: int, field: StringName, none: Variant) -> Variant:
	for item in list:
		if item.step == step:
			return item[field]
	for item in list:
		if item.step == -1:
			return item[field]
	return none
