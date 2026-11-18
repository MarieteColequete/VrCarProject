class_name LaneRules
extends RefCounted
## What a lane's rules say now, as pure functions of the world: its light, whether the lanes it
## gives way to are clear, and whether its crossings are in use. The traffic pipeline evaluates them
## on the main thread into each tick's snapshot, so road users read them as plain flags.


## The route of [param lane] this tick: the lane with its rules evaluated. [param agents] holds
## the road users; [param car] is the player's car, or null.
static func route_of(lane: LaneData, world: World, agents: AgentTable, car: CarState,
		lanes: Dictionary) -> TrafficSnapshot.Route:
	var r := TrafficSnapshot.Route.of(lane)
	if not lane.is_lane:
		return r
	if lane.light and world.has(Schema.LIGHT, lane.light):
		var state: int = world.get_value(Schema.LIGHT, lane.light, &"state")
		r.has_light = true
		r.light_red = LightLogic.is_red(state)
		r.light_amber = state == TrafficLight.Light.AMBER
	r.has_give_way = not lane.give_way_to.is_empty()
	if r.has_give_way:
		r.way_clear = way_is_clear(lane, agents, car, lanes)
	for crossing in lane.crossings:
		r.crossing_busy.append(crossing_in_use(crossing, agents))
	return r


## Whether pulling out at [param lane]'s stop line is safe: nothing on the priority lanes is due at
## the meeting point within the lane's safe gap, counting road users on those lanes, until their
## whole body has cleared it, and the player's car on them.
static func way_is_clear(lane: LaneData, agents: AgentTable, car: CarState,
		lanes: Dictionary) -> bool:
	var meeting := lane.point_at(lane.stop_at)
	for priority_id in lane.give_way_to:
		var priority: LaneData = lanes.get(priority_id)
		if priority == null:
			continue
		var at := priority.project(meeting).x
		for i in agents.size():
			if agents.lane[i] != priority_id:
				continue
			var clearing := absf(priority.project(agents.position[i]).x - at) < agents.body_size[i].z
			if clearing or agents.time_to(i, at, lanes) < lane.safe_gap:
				return false
		if car and vehicle_due(priority, car, at) < lane.safe_gap:
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
