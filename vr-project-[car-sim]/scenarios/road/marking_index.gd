class_name MarkingIndex
extends RefCounted
## The road markings of a scenario as 2D segments on the ground plane (X, Z), bucketed in a grid,
## so a query only tests the few segments near it. Built once when a scenario is baked, from each
## marking entity's kind, width, and points; queries return entity ids.

const CELL := 5.0
const NONE := []


class Segment:
	var marking := 0
	var a: Vector2
	var b: Vector2


var _cells := {}
var _kinds := {}
var _half_widths := {}


## Adds marking [param id] of [param kind], [param half_width] metres either side of [param points]
## (world space, along its curve).
func add(id: int, kind: int, half_width: float, points: PackedVector3Array) -> void:
	_kinds[id] = kind
	_half_widths[id] = half_width
	var margin := Vector2.ONE * (half_width + 0.5)
	for i in points.size() - 1:
		var seg := Segment.new()
		seg.marking = id
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


func kind_of(id: int) -> int:
	return _kinds.get(id, -1)


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
		var hit := Geo.crossing(a, move, seg.a, seg.b)
		if hit.x < 0.0:
			continue
		var edge := seg.b - seg.a
		var normal := Vector2(-edge.y, edge.x).normalized()
		if normal.dot(move) < 0.0:
			normal = -normal
		var at := a + move * hit.x
		hits.append(MarkingHit.new(seg.marking, _kinds[seg.marking], Vector3(at.x, from.y, at.y),
			Vector3(normal.x, 0.0, normal.y)))
	return hits


## The markings within their half width, plus [param extra] metres, of [param point].
func overlapping(point: Vector3, extra := 0.0) -> PackedInt64Array:
	var found := PackedInt64Array()
	var p := Vector2(point.x, point.z)
	for seg: Segment in _near(p, p):
		if found.has(seg.marking):
			continue
		var closest := Geometry2D.get_closest_point_to_segment(p, seg.a, seg.b)
		if p.distance_to(closest) <= float(_half_widths[seg.marking]) + extra:
			found.append(seg.marking)
	return found


## The segments in the cells covering [param lo] to [param hi], each once. Most queries fall in
## one cell, whose bucket is returned as it is, without copying. Nothing is written to the shared
## segments, so threads may query it, though reading them goes through the engine's object
## validation.
func _near(lo: Vector2, hi: Vector2) -> Array:
	var c0 := _cell(lo)
	var c1 := _cell(hi)
	if c0 == c1:
		return _cells.get(c0, NONE)
	var seen := {}
	var out := []
	for x in range(c0.x, c1.x + 1):
		for y in range(c0.y, c1.y + 1):
			var bucket: Variant = _cells.get(Vector2i(x, y))
			if bucket == null:
				continue
			for seg: Segment in bucket:
				if not seen.has(seg):
					seen[seg] = true
					out.append(seg)
	return out


static func _cell(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


static func _has_marking(hits: Array[MarkingHit], marking: int) -> bool:
	for hit in hits:
		if hit.marking == marking:
			return true
	return false
