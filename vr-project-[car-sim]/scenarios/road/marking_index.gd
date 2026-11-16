class_name MarkingIndex
extends RefCounted
## The road markings of a scenario as 2D segments on the ground plane (X, Z), bucketed in a grid,
## so a query only tests the few segments near it. A [Scenario] builds one on first use.

const CELL := 5.0

var _cells := {}
var _next_id := 0


func add(marking: RoadMarking) -> void:
	var points := marking.world_points()
	var margin := marking.half_width() + 0.5
	for i in points.size() - 1:
		var a := Vector2(points[i].x, points[i].z)
		var b := Vector2(points[i + 1].x, points[i + 1].z)
		var entry := {id = _next_id, marking = marking, a = a, b = b}
		_next_id += 1
		for cell in _cells_for(a.min(b) - Vector2.ONE * margin, a.max(b) + Vector2.ONE * margin):
			if not _cells.has(cell):
				_cells[cell] = []
			_cells[cell].append(entry)


## The markings a point moving from [param from] to [param to] crossed, at most one hit per
## marking: [code]{marking, point: Vector3, normal: Vector3}[/code], the normal pointing to the
## side it crossed onto.
func crossings(from: Vector3, to: Vector3) -> Array[Dictionary]:
	var hits: Array[Dictionary] = []
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	if a.is_equal_approx(b):
		return hits
	var seen := {}
	var move := b - a
	for entry in _near(a.min(b), a.max(b)):
		var marking: RoadMarking = entry.marking
		if seen.has(marking):
			continue
		var seg: Vector2 = entry.b - entry.a
		var denom := move.cross(seg)
		if is_zero_approx(denom):
			continue
		var offset: Vector2 = entry.a - a
		var t := offset.cross(seg) / denom
		var u := offset.cross(move) / denom
		if t <= 0.0 or t > 1.0 or u < 0.0 or u > 1.0:
			continue
		seen[marking] = true
		var normal := Vector2(-seg.y, seg.x).normalized()
		if normal.dot(move) < 0.0:
			normal = -normal
		var at := a + move * t
		hits.append({
			marking = marking,
			point = Vector3(at.x, from.y, at.y),
			normal = Vector3(normal.x, 0.0, normal.y),
		})
	return hits


## The markings within their half width, plus [param extra] metres, of [param point].
func overlapping(point: Vector3, extra := 0.0) -> Array[RoadMarking]:
	var found: Array[RoadMarking] = []
	var p := Vector2(point.x, point.z)
	for entry in _near(p, p):
		var marking: RoadMarking = entry.marking
		if found.has(marking):
			continue
		var closest := Geometry2D.get_closest_point_to_segment(p, entry.a, entry.b)
		if p.distance_to(closest) <= marking.half_width() + extra:
			found.append(marking)
	return found


func _near(lo: Vector2, hi: Vector2) -> Array:
	var out := []
	var seen := {}
	for cell in _cells_for(lo, hi):
		for entry in _cells.get(cell, []):
			if not seen.has(entry.id):
				seen[entry.id] = true
				out.append(entry)
	return out


func _cells_for(lo: Vector2, hi: Vector2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var c0 := Vector2i(floori(lo.x / CELL), floori(lo.y / CELL))
	var c1 := Vector2i(floori(hi.x / CELL), floori(hi.y / CELL))
	for x in range(c0.x, c1.x + 1):
		for y in range(c0.y, c1.y + 1):
			out.append(Vector2i(x, y))
	return out
