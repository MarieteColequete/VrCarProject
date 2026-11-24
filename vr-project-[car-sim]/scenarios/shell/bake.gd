class_name Bake
extends RefCounted
## Reads a scenario scene, the authoring side, into the [World]: markings, zones, bays, obstacles,
## lights, lanes, road users, sources, the rules of its checks, its steps, the ways its GPS shows,
## the session, and the player's car. Every node reference becomes an entity id, so nothing in the simulation holds a
## node. Once baked, the authoring nodes do nothing at runtime; the ones whose only role was to be
## simulated (road users) are listed in [member to_free] for the shell to remove.

var world: World
var scenario: Scenario
## The authoring nodes the views draw: entity to node (lights), and parked cars to their spawner.
var nodes := {}
## Nodes the simulation replaced, for the shell to free.
var to_free: Array[Node] = []

var _ids := {}
var _lanes := {}
var _lane_nodes := {}
var _filled := {}
var _steps: Array[ScenarioStep] = []


## Bakes [param p_scenario], driven by [param probe]'s car, into [param p_world].
static func scene(p_world: World, p_scenario: Scenario, probe: VehicleProbe) -> Bake:
	var bake := Bake.new()
	bake.world = p_world
	bake.scenario = p_scenario
	bake._run(probe)
	return bake


## The entity of an authored node; 0 for none.
func id_of(node: Node) -> int:
	return _ids.get(node, 0) if node else 0


func ids_of(list: Array) -> PackedInt64Array:
	var out := PackedInt64Array()
	for node: Node in list:
		var id := id_of(node)
		if id:
			out.append(id)
	return out


## The lane entity of a path, baking it on first use; 0 for none.
func lane_of(path: Path3D) -> int:
	if path == null or path.curve == null:
		return 0
	if _lane_nodes.has(path):
		return _lane_nodes[path]
	var settings := {name = path.name, is_lane = path is TrafficLane}
	if path is TrafficLane:
		var authored := path as TrafficLane
		settings.speed_limit = authored.speed_limit if authored.speed_limit > 0.0 else INF
		settings.stop_at = authored.stop_at()
		settings.safe_gap = authored.safe_gap
	var lane := LaneData.of(world.create(), path.curve, path.global_transform, settings)
	_lane_nodes[path] = lane.id
	_lanes[lane.id] = lane
	return lane.id


func lanes_of(paths: Array) -> PackedInt64Array:
	var out := PackedInt64Array()
	for path: Path3D in paths:
		var id := lane_of(path)
		if id:
			out.append(id)
	return out


## The index of a step among the scenario's; -1 for none.
func step_index(step: ScenarioStep) -> int:
	return _steps.find(step) if step else -1


func _run(probe: VehicleProbe) -> void:
	Schema.define(world)
	var all := scenario.nodes()
	for node in all:
		if node is TriggerZone or node is TrafficLight or node is ScriptedAgent \
				or node is ParkingBay:
			_ids[node] = world.create()
	_steps = scenario.get_steps()
	world.resources[Schema.STEPS] = _steps
	world.resources[Schema.DEFINITION] = scenario.definition
	world.resources[Schema.LANES] = _lanes
	world.spawn({vehicle = probe.spawn_values()})
	_markings(all)
	for node in all:
		if node is TriggerZone:
			_zone(node)
		elif node is ParkingBay:
			_bay(node)
		elif node is TrafficLight:
			_light(node)
	world.apply(obstacles(all))
	for node in all:
		if node is AgentSpawner:
			_spawner(node)
	for node in all:
		if node is TrafficLane:
			lane_of(node)
	_fill_lanes()
	for node in all:
		if node is ScriptedAgent:
			_agent(node)
		elif node is TrafficSource:
			world.spawn({source = node.values(self)})
	_fill_lanes()
	_rules()
	_routes(all)
	world.spawn({session = {state = ExamSession.State.BRIEFING, definition = scenario.definition,
		step_count = _steps.size()}})


func _markings(all: Array[Node]) -> void:
	var index := MarkingIndex.new()
	for node in all:
		var marking := node as RoadMarking
		if marking == null:
			continue
		var points := marking.world_points()
		var id := world.spawn({marking = {kind = marking.kind, half_width = marking.half_width(),
			points = points, name = marking.name}})
		index.add(id, marking.kind, marking.half_width(), points)
	world.resources[Schema.MARKINGS] = index


func _routes(all: Array[Node]) -> void:
	var routes: Array[Dictionary] = []
	for node in all:
		var route := node as GpsRoute
		if route:
			routes.append({step = step_index(route.step), points = route.world_points()})
	world.resources[Schema.ROUTES] = routes


func _zone(zone: TriggerZone) -> void:
	var box: Variant = zone.box_data()
	if box == null:
		push_warning("%s has no box shape; it is left out" % zone.get_path())
		return
	var values := {transform = box[0], half = box[1], name = zone.name}
	if zone is JunctionExit:
		values.merge({kind = &"junction_exit", side = zone.side, allowed = zone.allowed})
	elif zone is NoParkingZone:
		values.merge({kind = &"no_parking", reason = zone.reason})
	world.store(Schema.ZONE).add(_ids[zone], values)


func _bay(bay: ParkingBay) -> void:
	world.store(Schema.BAY).add(_ids[bay], {transform = bay.global_transform, size = bay.size,
		facing = bay.facing, reserved = bay.reserved, occupied = bay.occupied, name = bay.name})


func _light(light: TrafficLight) -> void:
	var values := {name = light.name, mode = light.mode, initial = light.initial,
		red_time = light.red_time, red_amber_time = light.red_amber_time,
		green_time = light.green_time, amber_time = light.amber_time,
		trigger = id_of(light.trigger), trigger_delay = light.trigger_delay}
	values.merge(LightLogic.initial(values), true)
	world.store(Schema.LIGHT).add(_ids[light], values)
	nodes[_ids[light]] = light


## Every box shape of a static body on a judged layer ([constant Layers.JUDGED]) among
## [param list], such as a parked van, and of the bodies of each node among it that keeps its own
## as internal children ([method Prop.bodies]): props, map assets, road signs, and traffic lights.
## Kerbs and pavements are not obstacles: the kerb lines judge them. Returns them as a delta
## spawning one obstacle a box.
static func obstacles(list: Array) -> Delta:
	var out := Delta.new()
	for node: Node in list:
		if node.has_method(&"bodies"):
			for body: StaticBody3D in node.call(&"bodies"):
				_body_obstacles(out, body, node.name)
			continue
		if node is StaticBody3D:
			_body_obstacles(out, node, node.name)
	return out


static func _body_obstacles(out: Delta, body: StaticBody3D, obstacle_name: StringName) -> void:
	if (body.collision_layer & Layers.JUDGED) == 0:
		return
	for child in body.get_children():
		var shape := child as CollisionShape3D
		if shape and shape.shape is BoxShape3D and not shape.disabled:
			out.spawn({obstacle = {transform = shape.global_transform,
				size = shape.shape.size, name = obstacle_name,
				pedestrian = (body.collision_layer & Layers.PEDESTRIAN) != 0}})


func _spawner(spawner: AgentSpawner) -> void:
	var bays := world.store(Schema.BAY)
	var eligible: Array[bool] = []
	for bay in spawner.bays:
		var id := id_of(bay)
		eligible.append(id != 0 and not bays.get_value(id, &"reserved")
			and not bays.get_value(id, &"occupied"))
	for index in spawner.choose(eligible):
		var bay := spawner.bays[index]
		bays.set_value(id_of(bay), &"occupied", true)
		var id := world.spawn({obstacle = {transform = bay.global_transform.translated_local(
			Vector3(0, 0.7, 0)), size = Vector3(1.8, 1.4, 4.2), name = bay.name}})
		nodes[id] = spawner


## Fills in the references of every lane baked so far (next lanes, neighbours, priority lanes,
## light, crossings), baking the lanes they name, until none is left unfilled.
func _fill_lanes() -> void:
	var pending := true
	while pending:
		pending = false
		for path: Path3D in _lane_nodes.keys():
			var id: int = _lane_nodes[path]
			if _filled.has(id):
				continue
			_filled[id] = true
			pending = true
			var lane: TrafficLane = path as TrafficLane
			if lane == null:
				continue
			var data: LaneData = _lanes[id]
			data.next = lanes_of(lane.next)
			data.left = lane_of(lane.left)
			data.right = lane_of(lane.right)
			data.give_way_to = lanes_of(lane.give_way_to)
			data.light = id_of(lane.light)
			for node in lane.crossings:
				var crossing := node as Crossing
				if crossing == null or crossing.zone == null or crossing.zone.box_data() == null:
					continue
				var zone := crossing.zone
				var box: Array = zone.box_data()
				var centre := data.project(zone.global_position).x
				data.crossings.append({zone = id_of(zone), transform = box[0], half = box[1],
					pedestrians = ids_of(crossing.pedestrians), margin = crossing.kerb_margin,
					stop = maxf(centre - maxf(box[1].x, box[1].z) - 1.0, 0.0)})


## Bakes a road user authored after the scene was baked, its lanes as well: a delta spawning it
## as entity [method id_of], empty when it has no path.
func agent_delta(agent: ScriptedAgent) -> Delta:
	if not _ids.has(agent):
		_ids[agent] = world.create()
	lane_of(agent.path)
	_fill_lanes()
	var values := _agent_values(agent)
	return Delta.new().spawn({agent = values}, _ids[agent]) if values else Delta.new()


## What a road user driving to its [member ScriptedAgent.destination] needs: where it starts on
## its lane, the lanes to take, and where to stop; nothing when it has no destination or its path
## is not a lane. Warns when the destination cannot be reached along the lanes.
func drive_to(agent: ScriptedAgent) -> Dictionary:
	if agent.destination == null or not agent.path is TrafficLane:
		return {}
	var lane: LaneData = _lanes.get(lane_of(agent.path))
	if lane == null:
		return {}
	var start_at := lane.project(agent.global_position).x
	var way := LaneRouter.route(_lanes, lane.id, start_at, agent.destination.global_position)
	if not way.reachable or not way.on_lane:
		push_warning("%s cannot reach %s along the lanes; it stops at the nearest point" % [
			agent.name, agent.destination.name])
	if not way.reachable:
		return {start_at = start_at}
	return {start_at = start_at, route = way.route, goal_lane = way.goal_lane,
		goal_at = way.goal_at}


func _agent(agent: ScriptedAgent) -> void:
	var values := _agent_values(agent)
	if values:
		world.store(Schema.AGENT).add(_ids[agent], values)
		to_free.append(agent)


## A road user's columns, standing on its lane; none, with a warning, when it has no path.
func _agent_values(agent: ScriptedAgent) -> Dictionary:
	var lane: LaneData = _lanes.get(lane_of(agent.path))
	if lane == null:
		push_warning("%s has no path; it is left out" % agent.get_path())
		return {}
	return AgentTable.spawn_values(agent.config(self), lane)


## [param script]'s static function [param method], or an empty [Callable] when it defines none.
static func _bound(script: Script, method: StringName) -> Callable:
	for info in script.get_script_method_list():
		if info.name == method:
			return Callable(script, method)
	return Callable()


func _rules() -> void:
	var policy := scenario.definition.policy if scenario.definition else null
	var order := 0
	for check in scenario.get_checks():
		var script := check.rule_script()
		var params := check.rule_params(self)
		for fault in check.fault_defs():
			if policy and policy.get_tier(fault.tier) == null:
				push_warning("%s: fault '%s' names tier '%s', which the policy does not define"
					% [check.name, fault.id, fault.tier])
		var active := PackedInt64Array()
		for step in check.active_steps:
			if step_index(step) >= 0:
				active.append(step_index(step))
		world.spawn({rule = {name = check.name, params = params,
			state = script.call(&"initial", params), active_steps = active, order = order,
			step = Callable(script, &"step"), finish = _bound(script, &"finish")}})
		order += 1
