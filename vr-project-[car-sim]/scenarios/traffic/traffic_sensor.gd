class_name TrafficSensor
extends RefCounted
## What a road user sees ahead: it sweeps a corridor of the user's width forward along its path,
## in a few straight segments that follow the curve, against the boxes of a [TrafficSnapshot], and
## reports the nearest one in the way, whatever it is: the player's car, another road user, a
## pedestrian, or a parked van. It sees what the snapshot holds: road users, vehicles with a
## [VehicleProbe], and the box shapes of static bodies on the obstacle layer. It reads only the
## snapshot, so it is safe on any thread.

## Straight segments the look-ahead is split into, so the sweep follows a curved path.
const SEGMENTS := 3


## Something in the way.
class Leader:
	## The body ahead; null for a stop line.
	var body: Node3D
	## Metres from the user's front to the body.
	var gap := INF
	## The body's speed along the user's direction, metres per second; negative when coming
	## towards it.
	var speed := 0.0
	## Whether the body is another road user.
	var road_user := false


## The nearest box in a corridor [param half_width] either side of [param points], the path ahead
## from the user's front, other than [param me]'s own; null when the way is clear.
static func sense(snapshot: TrafficSnapshot, points: PackedVector3Array, half_width: float,
		me: Node3D) -> Leader:
	# Local copies once, so the loops below read plain values instead of shared objects.
	var grid := snapshot.grid
	var ids := snapshot.ids
	var me_id := me.get_instance_id()
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
		var hit := -1
		for cx in range(c0.x, c1.x + 1):
			for cz in range(c0.y, c1.y + 1):
				var bucket: Variant = grid.get(Vector2i(cx, cz))
				if bucket == null:
					continue
				for index: int in bucket:
					# Compared by id: reading the node itself would validate it under a lock.
					if ids[index] == me_id:
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
						hit = index
		if hit >= 0:
			var leader := Leader.new()
			leader.gap = travelled + nearest
			leader.body = snapshot.nodes[hit]
			leader.speed = snapshot.velocity[hit].dot(dir)
			leader.road_user = snapshot.road_user[hit] == 1
			return leader
		travelled += length
	return null
