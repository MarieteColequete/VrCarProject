class_name LaneRules
extends RefCounted
## What a lane's rules say now, as pure functions of the world: its light, whether the lanes it
## gives way to are clear, and whether its crossings are in use. The traffic pipeline evaluates them
## on the main thread once a tick, into flags by lane slot, so road users read them as plain
## numbers.

## The flags of a tick, as indices into the array [method evaluate] returns.
enum { LIGHT_RED, LIGHT_AMBER, WAY_CLEAR, CROSSING_BUSY }


## The road users' rows by the lane they are on: lane entity to a [PackedInt32Array] of rows, in
## row order.
static func by_lane(agents: AgentTable) -> Dictionary:
	var out := {}
	for i in agents.size():
		var lane := agents.lane[i]
		if not out.has(lane):
			out[lane] = PackedInt32Array()
		out[lane].append(i)
	return out


## The flags of every lane in [param routes] that a road user stands on: per slot, its light shows
## red or red and amber, its light shows amber, its way is clear (1 when it gives way to nothing),
## and per crossing (flattened as in [RouteTable]) whether it is in use. Returned as
## [code][light_red, light_amber, way_clear, crossing_busy][/code], each a [PackedByteArray].
## [param buckets] is [method by_lane] of [param agents]; [param car] the player's car, or null.
static func evaluate(routes: RouteTable, world: World, agents: AgentTable, buckets: Dictionary,
		car: CarState, lanes: Dictionary) -> Array[PackedByteArray]:
	var n := routes.size()
	var red := PackedByteArray()
	var amber := PackedByteArray()
	var clear := PackedByteArray()
	var busy := PackedByteArray()
	red.resize(n)
	amber.resize(n)
	clear.resize(n)
	busy.resize(routes.crossing_stops.size())
	red.fill(0)
	amber.fill(0)
	clear.fill(1)
	busy.fill(0)
	for lane_id: int in buckets:
		var slot: int = routes.slots.get(lane_id, -1)
		if slot < 0 or not routes.is_lane[slot]:
			continue
		var light := routes.light[slot]
		if light and world.has(Schema.LIGHT, light):
			var state: int = world.get_value(Schema.LIGHT, light, &"state")
			red[slot] = 1 if LightLogic.is_red(state) else 0
			amber[slot] = 1 if state == TrafficLight.Light.AMBER else 0
		if routes.give_way_count[slot] > 0:
			clear[slot] = 1 if way_is_clear(routes, slot, agents, buckets, car, lanes) else 0
		var lane: LaneData = lanes[lane_id]
		for k in lane.crossings.size():
			if crossing_in_use(lane.crossings[k], agents):
				busy[routes.crossing_first[slot] + k] = 1
	return [red, amber, clear, busy]


## Whether pulling out at the stop line of lane [param slot] is safe: nothing on the priority lanes
## is due at the meeting point within the lane's safe gap, counting road users on those lanes, by
## their progress along them, until their whole body has cleared it, and the player's car on them.
static func way_is_clear(routes: RouteTable, slot: int, agents: AgentTable, buckets: Dictionary,
		car: CarState, lanes: Dictionary) -> bool:
	var gap := routes.safe_gap[slot]
	var first := routes.give_way_first[slot]
	for k in range(first, first + routes.give_way_count[slot]):
		var priority_id := routes.give_way_lane[k]
		var at := routes.give_way_at[k]
		var rows: Variant = buckets.get(priority_id)
		if rows != null:
			for i: int in rows:
				if absf(agents.progress[i] - at) < agents.body_size[i].z \
						or agents.time_to(i, at, lanes) < gap:
					return false
		if car and vehicle_due(lanes[priority_id], car, at) < gap:
			return false
	return true


## Seconds until the car, if on [param lane], reaches [param offset] along it; 0 when it is there,
## INF when it is not on the lane or already past.
static func vehicle_due(lane: LaneData, car: CarState, offset: float) -> float:
	var where := lane.project(car.position)
	if where.y > 2.5:
		return INF
	var remaining := offset - where.x
	if absf(remaining) <= car.body_length:
		return 0.0
	if remaining < 0.0:
		return INF
	return remaining / maxf(car.velocity.length(), 0.5)


## Whether any of [param crossing]'s pedestrians is on it or about to step onto it.
static func crossing_in_use(crossing: Dictionary, agents: AgentTable) -> bool:
	for walker: int in crossing.pedestrians:
		var i := agents.row_of(walker)
		if i >= 0 and not agents.is_done(i) \
				and Geo.point_in_box(crossing.transform, crossing.half, agents.position[i],
					crossing.margin):
			return true
	return false
