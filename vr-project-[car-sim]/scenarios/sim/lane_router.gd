class_name LaneRouter
extends RefCounted
## Finds a road user's way along the lanes to a point: from where it stands on its lane, the
## shortest chain of lanes, following each lane's next lanes, to the point of any lane nearest
## the destination. Pure: it reads the [LaneData] only, so a bake and a test get the same route.

## How far from a lane, metres, a destination still counts as on it: about a lane's half width
## and a margin. Beyond, the nearest lane is taken all the same, and [code]on_lane[/code] is
## false.
const ON_LANE := 2.5


## The way from [param from_at] metres along lane [param from] to the point of a reachable lane
## nearest [param point], among [param lanes] (entity to [LaneData]):
## [code]{reachable, on_lane, route, goal_lane, goal_at}[/code]. [code]route[/code] lists the
## lanes after the first, the choices to take at each fork; [code]goal_lane[/code] and
## [code]goal_at[/code] are where to stop. Unreachable when [param from] is not among them.
static func route(lanes: Dictionary, from: int, from_at: float, point: Vector3) -> Dictionary:
	var out := {reachable = false, on_lane = false, route = PackedInt64Array(), goal_lane = 0,
		goal_at = -1.0}
	if not lanes.has(from):
		return out
	# Dijkstra over lane ends: the cost of reaching a lane is the metres driven to its start.
	var cost := {from: -from_at}
	var came_from := {}
	var open: Array[int] = [from]
	var done := {}
	while not open.is_empty():
		var best := 0
		for i in open.size():
			if cost[open[i]] < cost[open[best]]:
				best = i
		var id := open[best]
		open.remove_at(best)
		if done.has(id):
			continue
		done[id] = true
		var lane: LaneData = lanes.get(id)
		if lane == null or not lane.is_lane:
			continue
		for next: int in lane.next:
			var through: float = cost[id] + lane.length
			if lanes.has(next) and (not cost.has(next) or through < cost[next]):
				cost[next] = through
				came_from[next] = id
				open.append(next)
	var goal := 0
	var goal_at := 0.0
	var nearest := INF
	var driven := INF
	for id: int in done:
		var lane: LaneData = lanes[id]
		if lane.curve == null:
			continue
		var hit := lane.project(point)
		# On the first lane, only what lies ahead of the start counts.
		if id == from and hit.x < from_at:
			continue
		var distance: float = cost[id] + hit.x
		if hit.y < nearest - 0.01 or (absf(hit.y - nearest) <= 0.01 and distance < driven):
			goal = id
			goal_at = hit.x
			nearest = hit.y
			driven = distance
	if goal == 0:
		return out
	var chain := PackedInt64Array()
	var at := goal
	while at != from and came_from.has(at):
		chain.append(at)
		at = came_from[at]
	chain.reverse()
	out.reachable = true
	out.on_lane = nearest <= ON_LANE
	out.route = chain
	out.goal_lane = goal
	out.goal_at = goal_at
	return out
