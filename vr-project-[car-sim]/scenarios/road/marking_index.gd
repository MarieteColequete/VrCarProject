class_name MarkingIndex
extends RefCounted
## The road markings of a scenario as 2D segments on the ground plane (X, Z), bucketed in a grid,
## so a query only tests the few segments near it. A [Scenario] builds one on first use.

const CELL := 5.0
const NONE := []


class Segment:
	var marking: RoadMarking
	var a: Vector2
	var b: Vector2
	## The last query that looked at this segment, so a segment in several cells is tested once.
	var stamp := -1


var _cells := {}
var _query := 0


func add(marking: RoadMarking) -> void:
	var points := marking.world_points()
	var margin := Vector2.ONE * (marking.half_width() + 0.5)
	for i in points.size() - 1:
		var seg := Segment.new()
		seg.marking = marking
		seg.a = Vector2(points[i].x, points[i].z)
		seg.b = Vector2(points[i + 1].x, points[i + 1].z)
		var c0 := _cell(seg.a.min(seg.b) - margin)
		var c1 := _cell(seg.a.max(seg.b) + margin)
		for x in range(c0.x, c1.x + 1):
			for y in range(c0.y, c1.y + 1):
				var cell := Vector2i(x, y)
				if not _cells.has(cell):
					_cells[cell] = []
				_cells[cell].append(seg)


## The markings a point moving from [param from] to [param to] crossed, at most one hit per
## marking.
func crossings(from: Vector3, to: Vector3) -> Array[MarkingHit]:
	var hits: Array[MarkingHit] = []
	var a := Vector2(from.x, from.z)
	var b := Vector2(to.x, to.z)
	if a.is_equal_approx(b):
		return hits
	var move := b - a
	for seg: Segment in _near(a.min(b), a.max(b)):
		if _has_marking(hits, seg.marking):
			continue
		var edge := seg.b - seg.a
		var denom := move.cross(edge)
		if is_zero_approx(denom):
			continue
		var offset := seg.a - a
		var t := offset.cross(edge) / denom
		var u := offset.cross(move) / denom
		if t <= 0.0 or t > 1.0 or u < 0.0 or u > 1.0:
			continue
		var normal := Vector2(-edge.y, edge.x).normalized()
		if normal.dot(move) < 0.0:
			normal = -normal
		var at := a + move * t
		hits.append(MarkingHit.new(seg.marking, Vector3(at.x, from.y, at.y),
			Vector3(normal.x, 0.0, normal.y)))
	return hits


## The markings within their half width, plus [param extra] metres, of [param point].
func overlapping(point: Vector3, extra := 0.0) -> Array[RoadMarking]:
	var found: Array[RoadMarking] = []
	var p := Vector2(point.x, point.z)
	for seg: Segment in _near(p, p):
		if found.has(seg.marking):
			continue
		var closest := Geometry2D.get_closest_point_to_segment(p, seg.a, seg.b)
		if p.distance_to(closest) <= seg.marking.half_width() + extra:
			found.append(seg.marking)
	return found


## The segments in the cells covering [param lo] to [param hi], each once. Most queries fall in
## one cell, whose bucket is returned as it is, without copying.
func _near(lo: Vector2, hi: Vector2) -> Array:
	var c0 := _cell(lo)
	var c1 := _cell(hi)
	if c0 == c1:
		return _cells.get(c0, NONE)
	_query += 1
	var out := []
	for x in range(c0.x, c1.x + 1):
		for y in range(c0.y, c1.y + 1):
			var bucket: Variant = _cells.get(Vector2i(x, y))
			if bucket == null:
				continue
			for seg in bucket:
				if seg.stamp != _query:
					seg.stamp = _query
					out.append(seg)
	return out


static func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


static func _has_marking(hits: Array[MarkingHit], marking: RoadMarking) -> bool:
	for hit in hits:
		if hit.marking == marking:
			return true
	return false
