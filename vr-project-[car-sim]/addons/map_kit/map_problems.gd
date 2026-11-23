@tool
class_name MapProblems
extends RefCounted
## A map's problems, listed as the Map Kit dock shows them: the nodes' configuration warnings and
## the kit's own checks, each with its fix where one is known.

const WARNING := &"warning"
const NOTICE := &"notice"


## Every problem of [param map] and its nodes, as
## [code]{node, message, severity, fix, fix_label}[/code]: the nodes' configuration warnings and
## the kit's own checks, the severity [constant WARNING] or [constant NOTICE], and a fix where
## one is known (null otherwise): a [Callable] that builds the [MapKitTools.Edit] when it is
## applied, so a list made and dropped on every check builds no nodes. One entry when [param map]
## is not a [RoadMap].
static func problems(map: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not map is RoadMap:
		out.append(_problem(map, "Open a map scene: its root needs to be a RoadMap."))
		return out
	var road_map := map as RoadMap
	var all: Array[Node] = [map]
	all.append_array(road_map.nodes())
	for node in all:
		if not node.has_method(&"_get_configuration_warnings"):
			continue
		for message: String in node.call(&"_get_configuration_warnings"):
			var entry := _problem(node, message)
			if node == map and message.contains("MapSpawn"):
				_fix(entry, "Add spawn", func() -> MapKitTools.Edit:
					return MapKitTools.Edit.new().add(map, _spawn_on_road(road_map)))
			elif node is TriggerZone and (node as TriggerZone).box_data() == null:
				var zone := node
				_fix(entry, "Add box", func() -> MapKitTools.Edit:
					return MapKitTools.Edit.new().add(zone, MapPalette.box(Vector3(4, 3, 4))))
			out.append(entry)
	for node in all:
		if node is RoadSegment:
			var segment := node as RoadSegment
			if segment.generated(RoadSegment.LANES).is_empty() \
					and segment.generated(RoadSegment.MARKINGS).is_empty():
				out.append(_fix(_problem(node, "The road has no lanes or markings yet."),
					"Generate", RoadNetwork.regenerate.bind(segment)))
	_lane_problems(road_map, out)
	_spawn_problems(road_map, out)
	if Terrain.of(road_map) == null:
		for node in road_map.nodes():
			if node is TerrainShape:
				out.append(_fix(_problem(node, "The map has no terrain for the shape to shape."),
					"Add terrain", TerrainAuthoring.add_terrain.bind(road_map)))
				break
	var lanes := {}
	for node in road_map.nodes():
		if node is ScriptedAgent and (node as ScriptedAgent).destination:
			if lanes.is_empty():
				lanes = RoadNetwork.lanes_of(road_map)
			var way := RoadNetwork.way_of(road_map, node, lanes)
			if not way.is_empty() and (not way.reachable or not way.on_lane):
				out.append(_problem(node, "It cannot reach %s along the lanes; link the lanes "
					% (node as ScriptedAgent).destination.name + "on its way, or move the "
					+ "checkpoint onto one."))
	return out


static func _lane_problems(map: RoadMap, out: Array[Dictionary]) -> void:
	var lanes: Array = []
	var placed := {}
	for node in map.nodes():
		if node is TrafficLane and (node as TrafficLane).length() > 0.0:
			lanes.append(node)
			placed[node] = RoadMap.to_map(node, map)
	var links := RoadNetwork.lane_links(lanes, 1.0, placed)
	for lane: TrafficLane in lanes:
		if links.has(lane):
			var next := RoadNetwork.with_links(lane, links[lane])
			var names := ", ".join(links[lane].map(func(l: TrafficLane) -> String: return l.name))
			var message := "The lane ends where %s starts but is not linked." % names
			out.append(_fix(_problem(lane, message), "Connect", func() -> MapKitTools.Edit:
				return MapKitTools.Edit.new().set_value(lane, &"next", next)))
		elif lane.next.is_empty():
			out.append(_problem(lane, "The lane leads nowhere; road users leave the map there.",
				NOTICE))


static func _spawn_problems(map: RoadMap, out: Array[Dictionary]) -> void:
	var spawns := map.spawns()
	var has_roads := _has_roads(map)
	for i in spawns.size():
		var at := RoadMap.to_map(spawns[i], map).origin
		if has_roads and not RoadNetwork.on_road(map, at):
			out.append(_problem(spawns[i], "The spawn is not on a road.", NOTICE))
		for j in range(i + 1, spawns.size()):
			if at.distance_to(RoadMap.to_map(spawns[j], map).origin) < 2.0:
				out.append(_problem(spawns[j], "The spawn overlaps %s." % spawns[i].name, NOTICE))


static func _has_roads(map: Node) -> bool:
	return MapKitTools.nodes_of(map).any(func(n: Node) -> bool: return n is RoadSegment or n is RoadJunction)


static func _problem(node: Node, message: String, severity := WARNING) -> Dictionary:
	return {node = node, message = message, severity = severity, fix = null, fix_label = ""}


## Gives [param entry] its fix: [param make] builds the [MapKitTools.Edit] when it is applied.
static func _fix(entry: Dictionary, label: String, make: Callable) -> Dictionary:
	entry.fix = make
	entry.fix_label = label
	return entry


## A spawn on the map's first lane, two metres in, facing along it; at the origin without lanes.
static func _spawn_on_road(map: RoadMap) -> MapSpawn:
	var spawn := MapPalette.spawn() as MapSpawn
	for node in map.nodes():
		if node is TrafficLane and (node as TrafficLane).length() > 4.0:
			var lane := node as TrafficLane
			var into := RoadMap.to_map(lane, map)
			var at := into * lane.curve.sample_baked(2.0)
			var ahead := into * lane.curve.sample_baked(3.0) - at
			ahead.y = 0.0
			spawn.transform = Transform3D(Basis.looking_at(ahead.normalized()), at)
			break
	return spawn
