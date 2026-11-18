class_name TrafficSensor
extends RefCounted
## What a road user sees ahead: it sweeps a corridor of the user's width forward along its path,
## in a few straight segments that follow the curve, against the boxes of a [TrafficSnapshot], and
## reports the nearest one in the way, whatever it is: the player's car, another road user, a
## pedestrian, or a parked van. It sees what the snapshot holds: road users, the player's car, and
## the scenario's obstacles. It reads only the snapshot, so it is safe on any thread.

## Straight segments the look-ahead is split into, so the sweep follows a curved path.
const SEGMENTS := 3


## The nearest box in a corridor [param half_width] either side of [param points], the path ahead
## from the user's front, other than entity [param me]'s own. When there is one it returns true and
## writes into [param hit]: [code][1, entity, gap from the user's front, its speed along the
## user's direction (negative when coming towards it), 1 if a road user][/code]; when the way is
## clear it returns false, leaving [param hit] as it was. It reads only the snapshot and creates no
## object, so it is safe and cheap on any thread.
static func sense(snapshot: TrafficSnapshot, points: PackedVector3Array, half_width: float,
		me: int, hit: PackedFloat64Array) -> bool:
	# Local copies once, so the loops below read plain values instead of shared objects.
	var grid := snapshot.grid
	var ids := snapshot.ids
	var corners := snapshot.corners
	var centres := snapshot.centre
	var alongs := snapshot.along
	var acrosses := snapshot.across
	var half_lengths := snapshot.half_length
	var half_widths := snapshot.half_width
	var travelled := 0.0
	for i in points.size() - 1:
		var a := Vector2(points[i].x, points[i].z)
		var b := Vector2(points[i + 1].x, points[i + 1].z)
		var length := a.distance_to(b)
		if length < 0.01:
			continue
		var dir := (b - a) / length
		var side := Vector2(-dir.y, dir.x)
		var mid := a + dir * length * 0.5
		var half_len := length * 0.5
		var pad := Vector2.ONE * (half_width + 0.5)
		var c0 := TrafficSnapshot.cell_of(a.min(b) - pad)
		var c1 := TrafficSnapshot.cell_of(a.max(b) + pad)
		var nearest := INF
		var nearest_index := -1
		for cx in range(c0.x, c1.x + 1):
			for cz in range(c0.y, c1.y + 1):
				var bucket: Variant = grid.get(Vector2i(cx, cz))
				if bucket == null:
					continue
				for index: int in bucket:
					if ids[index] == me:
						continue
					# The corridor's own axes: the box's corners must reach it.
					var u_min := INF
					var u_max := -INF
					var v_min := INF
					var v_max := -INF
					for k in 4:
						var rel := corners[index * 4 + k] - a
						var u := rel.dot(dir)
						var v := rel.dot(side)
						u_min = minf(u_min, u)
						u_max = maxf(u_max, u)
						v_min = minf(v_min, v)
						v_max = maxf(v_max, v)
					if u_max < 0.0 or u_min > length or v_max < -half_width or v_min > half_width:
						continue
					# The box's axes: the corridor must reach the box.
					var to_mid := mid - centres[index]
					var axis := alongs[index]
					if absf(to_mid.dot(axis)) > half_lengths[index] \
							+ absf(dir.dot(axis)) * half_len + absf(side.dot(axis)) * half_width:
						continue
					axis = acrosses[index]
					if absf(to_mid.dot(axis)) > half_widths[index] \
							+ absf(dir.dot(axis)) * half_len + absf(side.dot(axis)) * half_width:
						continue
					var entry := maxf(u_min, 0.0)
					if entry < nearest:
						nearest = entry
						nearest_index = index
		if nearest_index >= 0:
			hit[0] = 1.0
			hit[1] = ids[nearest_index]
			hit[2] = travelled + nearest
			hit[3] = snapshot.velocity[nearest_index].dot(dir)
			hit[4] = float(snapshot.road_user[nearest_index])
			return true
		travelled += length
	return false
