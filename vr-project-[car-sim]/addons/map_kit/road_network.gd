@tool
class_name RoadNetwork
extends RefCounted
## A map's roads and lanes as Map Kit shapes them: the open road ends and placing a road or
## junction onto one, extending a road, generating lanes and markings, linking lanes whose ends
## meet, the lane nearest a place, and road users sent to a checkpoint along the lanes.

## Road ends closer than this, metres, are joined.
const JOIN := 0.5
## How far a piece snaps onto an open road end, metres.
const SNAP_REACH := 3.0
## Length of a road added by extending, metres.
const EXTENSION := 20.0


## The lanes each of [param lanes] continues onto and does not list yet: every other lane whose
## start lies within [param gap] metres of its end, heading on the same way. [param placed] gives
## a lane's transform into a common space when it is not the lane's global one, as for lanes not
## yet in the tree.
static func lane_links(lanes: Array, gap := 1.0, placed := {}) -> Dictionary:
	var links := {}
	for a: TrafficLane in lanes:
		if a.curve == null or a.length() <= 0.0:
			continue
		var end := _lane_point(a, a.length(), placed)
		var heading := end - _lane_point(a, a.length() - 0.5, placed)
		for b: TrafficLane in lanes:
			if b == a or b.curve == null or b.length() <= 0.0 or a.next.has(b):
				continue
			var start := _lane_point(b, 0.0, placed)
			var onward := _lane_point(b, 0.5, placed) - start
			var aligned := heading.normalized().dot(onward.normalized()) > 0.5
			if start.distance_to(end) <= gap and aligned:
				if not links.has(a):
					links[a] = [] as Array[TrafficLane]
				links[a].append(b)
	return links


## Every road end of [param map] that no other road joins, in the map's space:
## [code]{transform, width, node}[/code], the transform facing out of the road along -Z.
static func road_ends(map: Node) -> Array[Dictionary]:
	var all := _all_road_ends(map)
	var open: Array[Dictionary] = []
	for a in all:
		var joined := false
		for b in all:
			if b.node != a.node and a.transform.origin.distance_to(b.transform.origin) <= JOIN:
				joined = true
				break
		if not joined:
			open.append(a)
	return open


## The open road end of [param map] nearest [param point], within [param reach] metres; empty
## when there is none. [param ends] are the map's [method road_ends] when the caller keeps them,
## so a mouse moving over the map does not look for them again each time.
static func nearest_end(map: Node, point: Vector3, reach := SNAP_REACH,
		ends: Array[Dictionary] = []) -> Dictionary:
	var best := {}
	var best_distance := reach
	for end in ends if not ends.is_empty() else road_ends(map):
		var distance: float = end.transform.origin.distance_to(point)
		if distance <= best_distance:
			best = end
			best_distance = distance
	return best


## Where a road or junction [param node] placed at [param point] goes to join the open road end
## nearest it: its transform in the map's space; null when no end is near. It also shapes
## [param node] to fit the end: a junction's road width, a road's curve and lane width. [param ends]
## as for [method nearest_end].
static func joining_transform(map: Node, node: Node3D, point: Vector3,
		ends: Array[Dictionary] = []) -> Variant:
	var end := nearest_end(map, point, SNAP_REACH, ends)
	if end.is_empty():
		return null
	if node is RoadJunction:
		var junction := node as RoadJunction
		junction.road_width = end.width
		var arm := junction.arm_end(RoadJunction.Arm.SOUTH)
		return _facing_back(end.transform) * arm.affine_inverse()
	if node is RoadSegment:
		var segment := node as RoadSegment
		segment.curve = MapKitTools.straight_from(EXTENSION)
		var lanes := segment.lanes_each_way * (1.0 if segment.one_way else 2.0)
		segment.lane_width = end.width / lanes
		return end.transform
	return null


## Adds a road from the open end of [param road] nearest [param near], with the same lanes:
## [constant EXTENSION] metres straight on. Empty when the road has no open end.
static func extend_road(map: Node, road: Node3D, near := Vector3.INF) -> MapKitTools.Edit:
	var end := _end_of(map, road, near)
	if end.is_empty():
		return MapKitTools.Edit.new()
	var segment := MapPalette.road(road is RoadSegment and (road as RoadSegment).one_way)
	segment.curve = MapKitTools.straight_from(EXTENSION)
	if road is RoadSegment:
		var from := road as RoadSegment
		segment.lanes_each_way = from.lanes_each_way
		segment.lane_width = from.lane_width
		segment.speed_limit_kmh = from.speed_limit_kmh
		segment.centre = from.centre
		segment.kerbs = from.kerbs
	else:
		segment.lane_width = (road as RoadJunction).road_width / 2.0
	var parent := road.get_parent()
	segment.transform = RoadMap.to_map(parent, map).affine_inverse() * end.transform
	return MapKitTools.Edit.new().add(parent, segment)


## Adds a junction of [param shape] on the open end of [param road] nearest [param near], joined
## by its south arm. Empty when the road has no open end.
static func junction_at_end(map: Node, road: Node3D, shape: RoadJunction.Shape,
		near := Vector3.INF) -> MapKitTools.Edit:
	var end := _end_of(map, road, near)
	if end.is_empty():
		return MapKitTools.Edit.new()
	var junction := MapPalette.junction(shape) as RoadJunction
	var at: Variant = joining_transform(map, junction, end.transform.origin)
	var parent := road.get_parent()
	junction.transform = RoadMap.to_map(parent, map).affine_inverse() * (at as Transform3D)
	return MapKitTools.Edit.new().add(parent, junction)


## Regenerates every road's and junction's lanes, markings, and lines in [param map], and links
## all its lanes whose ends meet.
static func generate_all(map: Node) -> MapKitTools.Edit:
	var edit := MapKitTools.Edit.new()
	for node in MapKitTools.nodes_of(map):
		if node is RoadSegment or node is RoadJunction:
			edit.merge(regenerate(node))
	return edit.merge(link_lanes(map, edit))


## Replaces what [param road], a [RoadSegment] or [RoadJunction], generated: its lanes and
## markings, or its lines and lanes.
static func regenerate(road: Node3D) -> MapKitTools.Edit:
	var edit := MapKitTools.Edit.new()
	if road is RoadSegment:
		var segment := road as RoadSegment
		for old in segment.generated(RoadSegment.LANES) + segment.generated(RoadSegment.MARKINGS):
			edit.remove(old)
		for made: Node in segment.make_lanes() + segment.make_markings():
			edit.add(segment, made)
	elif road is RoadJunction:
		var junction := road as RoadJunction
		for old in junction.generated(RoadJunction.LINES) \
				+ junction.generated(RoadJunction.LANES) + _old_junction_lines(junction):
			edit.remove(old)
		for made: Node in junction.make_lines() + junction.make_lanes():
			edit.add(junction, made)
	return edit


## Links the lanes of [param map] whose ends meet, after [param pending] (an edit not yet made)
## and with what it removes taken out of every lane's links.
static func link_lanes(map: Node, pending: MapKitTools.Edit = null) -> MapKitTools.Edit:
	var edit := MapKitTools.Edit.new()
	var removed: Array[Node] = []
	if pending:
		removed = pending.removes
	var placed := {}
	var lanes: Array[TrafficLane] = []
	for node in MapKitTools.nodes_of(map):
		if node is TrafficLane and not removed.has(node) and not _inside(node, removed):
			lanes.append(node)
			placed[node] = RoadMap.to_map(node, map)
	var fresh: Array[TrafficLane] = []
	if pending:
		for pair: Array in pending.adds:
			for node in MapKitTools.with_descendants(pair[1]):
				if node is TrafficLane:
					fresh.append(node)
					placed[node] = RoadMap.to_map(pair[0], map) * RoadMap.to_map(node, pair[1])
	var all: Array = lanes + fresh
	var links := lane_links(all, 1.0, placed)
	for lane in all:
		var kept: Array[TrafficLane] = []
		for other in lane.next:
			if other != null and not removed.has(other):
				kept.append(other)
		var joined: Array = links.get(lane, [])
		if kept.size() == lane.next.size() and joined.is_empty():
			continue
		kept.append_array(joined)
		if fresh.has(lane):
			lane.next = kept
		else:
			edit.set_value(lane, &"next", kept)
	return edit


## The lane of [param map] nearest [param place] (in the map's space) that runs the way it faces,
## within [param reach] metres; null when none does.
static func nearest_lane(map: Node, place: Transform3D, reach := 6.0) -> TrafficLane:
	var ahead := -place.basis.z
	ahead.y = 0.0
	var best: TrafficLane = null
	var best_distance := reach
	for node in MapKitTools.nodes_of(map):
		var lane := node as TrafficLane
		if lane == null or lane.length() <= 0.0:
			continue
		var into := RoadMap.to_map(lane, map)
		var local := into.affine_inverse() * place.origin
		var at := lane.curve.get_closest_offset(local)
		var point := into * lane.curve.sample_baked(at)
		var onward := into * lane.curve.sample_baked(minf(at + 0.5, lane.length())) \
			- into * lane.curve.sample_baked(maxf(at - 0.5, 0.0))
		onward.y = 0.0
		var distance := Vector2(point.x - place.origin.x, point.z - place.origin.z).length()
		if ahead.length() > 0.0 and onward.normalized().dot(ahead.normalized()) < 0.3:
			continue
		if distance < best_distance:
			best = lane
			best_distance = distance
	return best


## Makes each car of [param cars] (a [MapAsset], a car or van [Prop], or a [ScriptedAgent])
## a road user that drives to [param checkpoint]: a [ScriptedAgent] in its place, on the lane
## nearest it that runs its way, with its model, size, and the lane's speed limit, reacting to
## traffic on the way. A road user already is one, and only gets the destination. Cars with no
## lane near them are left as they are.
static func drive_to(map: Node, cars: Array, checkpoint: Node3D) -> MapKitTools.Edit:
	var edit := MapKitTools.Edit.new()
	var parent: Node = map.get_node_or_null("Traffic")
	if parent == null:
		parent = map
	for car: Node in cars:
		if car is ScriptedAgent:
			edit.set_value(car, &"destination", checkpoint)
			continue
		if not (car is MapAsset or car is Prop):
			continue
		var place := RoadMap.to_map(car, map)
		var lane := nearest_lane(map, place)
		if lane == null:
			continue
		var agent := ScriptedAgent.new()
		agent.name = String(car.name) + "Driver"
		agent.transform = RoadMap.to_map(parent, map).affine_inverse() * place
		agent.path = lane
		agent.destination = checkpoint
		agent.speed = lane.speed_limit if lane.speed_limit > 0.0 else 50.0 / 3.6
		agent.colour = Color.WHITE
		if car is MapAsset:
			agent.model = (car as MapAsset).model
			agent.body_size = (car as MapAsset).size()
		else:
			agent.model = (car as Prop).model()
			agent.body_size = (car as Prop).box_size()
		edit.remove(car)
		edit.add(parent, agent)
	return edit


## The way [param agent] takes to its destination along the lanes of [param map], as
## [method LaneRouter.route] gives it; empty when it has no destination or no lane. [param lanes]
## are the map's [method lanes_of] when the caller keeps them for several road users.
static func way_of(map: Node, agent: ScriptedAgent, lanes := {}) -> Dictionary:
	if agent.destination == null or not agent.path is TrafficLane:
		return {}
	if lanes.is_empty():
		lanes = lanes_of(map)
	var from: LaneData = lanes.get(agent.path.get_instance_id())
	if from == null:
		return {}
	var start := from.project(RoadMap.to_map(agent, map).origin).x
	return LaneRouter.route(lanes, from.id, start, RoadMap.to_map(agent.destination, map).origin)


## The lanes of [param map] as [LaneData] by instance id, in the map's space, with their links.
static func lanes_of(map: Node) -> Dictionary:
	var lanes := {}
	for node in MapKitTools.nodes_of(map):
		var lane := node as TrafficLane
		if lane and lane.length() > 0.0:
			lanes[lane.get_instance_id()] = LaneData.of(lane.get_instance_id(), lane.curve,
				RoadMap.to_map(lane, map), {is_lane = true,
					next = PackedInt64Array(lane.next.filter(func(n: TrafficLane) -> bool:
						return n != null).map(func(n: TrafficLane) -> int:
							return n.get_instance_id()))})
	return lanes


## Whether [param point], in the map's space, lies on one of [param map]'s roads or junctions.
static func on_road(map: Node, point: Vector3) -> bool:
	for node in MapKitTools.nodes_of(map):
		if node is RoadSegment:
			var segment := node as RoadSegment
			var into := RoadMap.to_map(segment, map)
			var reach := sqrt(pow(segment.width() / 2.0, 2) + pow(RoadSegment.STEP / 2.0, 2)) + 0.25
			for frame: Array in segment.frames():
				var at: Vector3 = into * frame[0]
				if Vector2(at.x - point.x, at.z - point.z).length() <= reach:
					return true
		elif node is RoadJunction:
			var junction := node as RoadJunction
			var local := RoadMap.to_map(junction, map).affine_inverse() * point
			if junction.distance_outside(local) <= 0.0:
				return true
	return false


static func _all_road_ends(map: Node) -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	for node in MapKitTools.nodes_of(map):
		if node is RoadSegment:
			var segment := node as RoadSegment
			var into := RoadMap.to_map(segment, map)
			for end in segment.ends():
				all.append({transform = into * end, width = segment.width(), node = segment})
		elif node is RoadJunction:
			var junction := node as RoadJunction
			var into := RoadMap.to_map(junction, map)
			for arm in junction.arms():
				all.append({transform = into * junction.arm_end(arm), width = junction.road_width,
					node = junction})
	return all


static func _end_of(map: Node, road: Node, near: Vector3) -> Dictionary:
	var best := {}
	var best_distance := INF
	for end in road_ends(map):
		if end.node != road:
			continue
		var distance: float = 0.0 if near == Vector3.INF \
			else end.transform.origin.distance_to(near)
		if best.is_empty() or distance < best_distance:
			best = end
			best_distance = distance
	return best


## [param end] turned to face back the way it came.
static func _facing_back(end: Transform3D) -> Transform3D:
	return Transform3D(end.basis.rotated(Vector3.UP, PI), end.origin)


## Lines generated before the junction told lines from lanes.
static func _old_junction_lines(junction: RoadJunction) -> Array[Node]:
	var out: Array[Node] = []
	for child in junction.get_children():
		if child.get_meta(RoadJunction.GENERATED, null) is bool:
			out.append(child)
	return out


static func _inside(node: Node, ancestors: Array[Node]) -> bool:
	for ancestor in ancestors:
		if ancestor.is_ancestor_of(node):
			return true
	return false


static func _lane_point(lane: TrafficLane, offset: float, placed: Dictionary) -> Vector3:
	var into: Transform3D = placed[lane] if placed.has(lane) \
		else (lane.global_transform if lane.is_inside_tree() else Transform3D.IDENTITY)
	return into * lane.curve.sample_baked(clampf(offset, 0.0, lane.length()))


## Links the lanes among [param picked] whose ends meet, or, with fewer than two picked, all of
## [param map]'s ([method link_lanes]).
static func connect_lanes(map: Node, picked: Array) -> MapKitTools.Edit:
	var lanes := picked.filter(func(n: Node) -> bool: return n is TrafficLane)
	if lanes.size() < 2:
		return link_lanes(map)
	var edit := MapKitTools.Edit.new()
	var links := lane_links(lanes)
	for lane: TrafficLane in links:
		edit.set_value(lane, &"next", with_links(lane, links[lane]))
	return edit


## [param lane]'s next lanes with [param more] added.
static func with_links(lane: TrafficLane, more: Array) -> Array[TrafficLane]:
	var next: Array[TrafficLane] = lane.next.duplicate()
	next.append_array(more)
	return next


## The checkpoint the cars among [param picked] drive to: the one picked with them, else the map's
## only one; null when that is not exactly one.
static func checkpoint_for(map: RoadMap, picked: Array) -> Checkpoint:
	var checkpoints := picked.filter(func(n: Node) -> bool: return n is Checkpoint)
	if checkpoints.is_empty():
		checkpoints = map.nodes().filter(func(n: Node) -> bool: return n is Checkpoint)
	return checkpoints[0] if checkpoints.size() == 1 else null
