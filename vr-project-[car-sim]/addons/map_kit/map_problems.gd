@tool
class_name MapProblems
extends RefCounted
## A map's problems, listed as the Map Kit dock shows them: the nodes' configuration warnings and
## the kit's own checks, each with its fix where one is known.

const WARNING := &"warning"
const NOTICE := &"notice"
## How near a lane, metres, a solid thing stands in road users' way: half a car's width and a little.
const LANE_CLEARANCE := 1.0
## How far past a lane's ends, metres, road users still need the way clear: half a car's length and
## a little, since a road user leaves the map only once its middle reaches the end.
const LANE_END_CLEARANCE := 2.5


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
	_model_problems(road_map, out)
	_in_the_way_problems(road_map, out)
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


## Loose models, which nothing collides with and whose look the kit cannot change, and meshes that
## show nothing.
static func _model_problems(map: RoadMap, out: Array[Dictionary]) -> void:
	var models := AssetTools.loose_models(map.get_children())
	for model in models:
		out.append(_fix(_problem(model, "The model is loose: nothing collides with it, road users "
			+ "do not see it, and Next look cannot change it."), "Make map asset",
			AssetTools.make_map_assets.bind([model])))
	for node in map.nodes():
		if _shows_nothing(node) and not models.any(func(m: Node) -> bool: return m.is_ancestor_of(node)):
			var empty := node
			out.append(_fix(_problem(node, "It shows nothing.", NOTICE), "Delete",
				func() -> MapKitTools.Edit: return MapKitTools.Edit.new().remove(empty)))


## Solid things in road users' way (props, map assets, road signs, and traffic lights): on a lane,
## or on a road user's path, or just past either's end. Road users stop at them, and traffic backs
## up behind.
static func _in_the_way_problems(map: RoadMap, out: Array[Dictionary]) -> void:
	var ways: Array = []
	for node in map.nodes():
		var way: Path3D = null
		if node is TrafficLane:
			way = node
		elif node is ScriptedAgent and not (node as ScriptedAgent).pedestrian:
			way = (node as ScriptedAgent).path
		if way and way.curve and way.curve.point_count > 1:
			var points := _way_points(way, map)
			if not ways.any(func(w: Array) -> bool: return w[0] == way):
				ways.append([way, points, _points_area(points).grow(LANE_CLEARANCE)])
	if ways.is_empty():
		return
	for node in map.nodes():
		if not node.has_method(&"bodies") or (node is MapAsset and (node as MapAsset).mesh_collider):
			continue
		for body: StaticBody3D in node.call(&"bodies"):
			var blocked := _blocked_ways(body, map, ways)
			if not blocked.is_empty():
				var entry := _problem(node, "It stands in the way of road users on %s: they "
					% ", ".join(blocked) + "stop at it, and traffic backs up behind.")
				if node is MapAsset:
					var asset := node as MapAsset
					_fix(entry, "Make look only", func() -> MapKitTools.Edit:
						return MapKitTools.Edit.new().set_value(asset, &"body_type", null))
				out.append(entry)
				break


## The points along [param way] every half metre in the map's space, flat, and past each end by
## [constant LANE_END_CLEARANCE].
static func _way_points(way: Path3D, map: RoadMap) -> PackedVector2Array:
	var into := RoadMap.to_map(way, map)
	var curve := way.curve
	var length := curve.get_baked_length()
	var out := PackedVector2Array()
	var steps := maxi(1, ceili(length / 0.5))
	for i in steps + 1:
		var at := into * curve.sample_baked(length * i / steps)
		out.append(Vector2(at.x, at.z))
	for end: Array in [[0, 1], [out.size() - 1, out.size() - 2]]:
		var tip: Vector2 = out[end[0]]
		var outward: Vector2 = (tip - out[end[1]]).normalized()
		var d := 0.5
		while d <= LANE_END_CLEARANCE:
			out.append(tip + outward * d)
			d += 0.5
	return out


static func _points_area(points: PackedVector2Array) -> Rect2:
	var out := Rect2(points[0], Vector2.ZERO)
	for point in points:
		out = out.expand(point)
	return out


## The names of the ways in [param ways] that come within [constant LANE_CLEARANCE] of
## [param body]'s boxes, on the ground plan.
static func _blocked_ways(body: StaticBody3D, map: RoadMap, ways: Array) -> PackedStringArray:
	var out := PackedStringArray()
	for shape in body.get_children():
		if not shape is CollisionShape3D or not (shape as CollisionShape3D).shape is BoxShape3D:
			continue
		var placed := RoadMap.to_map(shape, map)
		var half := ((shape as CollisionShape3D).shape as BoxShape3D).size / 2.0
		var scaled := placed.basis.get_scale()
		var flat := Vector2(half.x * scaled.x, half.z * scaled.z) + Vector2.ONE * LANE_CLEARANCE
		var inverse := placed.affine_inverse()
		var reach := Geo.ground_area(placed, flat / Vector2(scaled.x, scaled.z))
		for way: Array in ways:
			if out.has((way[0] as Node).name) or not (way[2] as Rect2).intersects(reach):
				continue
			for point: Vector2 in way[1]:
				var local := inverse * Vector3(point.x, placed.origin.y, point.y)
				if absf(local.x * scaled.x) < flat.x and absf(local.z * scaled.z) < flat.y:
					out.append((way[0] as Node).name)
					break
	return out


## Whether [param node] is a mesh or a multimesh with nothing to draw and nothing under it.
static func _shows_nothing(node: Node) -> bool:
	if node.get_child_count() > 0:
		return false
	if node is MultiMeshInstance3D:
		var many := (node as MultiMeshInstance3D).multimesh
		return many == null or many.mesh == null or many.instance_count == 0
	return node.get_class() == "MeshInstance3D" and node.get_script() == null \
		and (node as MeshInstance3D).mesh == null


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
