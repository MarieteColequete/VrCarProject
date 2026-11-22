@tool
class_name MapKitTools
extends RefCounted
## What the Map Kit editor plugin does to a map, kept apart from the editor so it runs and is
## tested headless: the palette, creating, renaming, duplicating, and deleting maps, extending
## roads and generating their lanes and markings, linking lanes whose ends meet, giving a mesh a
## solid body, adding terrain and draping a map's roads and places on it, and listing a map's
## problems with their fixes. Changes to an open map come back as
## an [MapKitTools.Edit], which the plugin applies with undo and a test applies directly.

const BASE := "res://scenarios/kit/map_base.tscn"
const ASPHALT := preload("res://scenarios/kit/asphalt.tres")
const ICONS := "res://addons/map_kit/icons/"
## Where the scenarios that may use a map live.
const USERS_ROOT := "res://scenarios/"
## Road ends closer than this, metres, are joined.
const JOIN := 0.5
## How far a piece snaps onto an open road end, metres.
const SNAP_REACH := 3.0
## Length of a road added by extending, metres.
const EXTENSION := 20.0

const WARNING := &"warning"
const NOTICE := &"notice"


## One entry of the palette: its button text, the section it is listed under, the map node it is
## added under, its icon, a tooltip, and the function building it.
class Piece:
	extends RefCounted
	var label: String
	var section: String
	var group: String
	var make: Callable
	## An editor theme icon's name, or a path to an icon of the kit's own.
	var icon: String
	var tip: String
	## Whether it joins an open road end when placed near one.
	var joins_roads := false
	## How far it is turned about the vertical when placed, radians.
	var turn := 0.0

	func _init(p_label: String, p_section: String, p_group: String, p_make: Callable,
			p_icon := "", p_tip := "") -> void:
		label = p_label
		section = p_section
		group = p_group
		make = p_make
		icon = p_icon
		tip = p_tip


## A change to an open map: nodes to remove, nodes to add, and properties to set, in that order.
## The plugin turns it into one undo action; [method apply] makes it at once.
class Edit:
	extends RefCounted
	## [code][parent, node][/code] pairs.
	var adds: Array = []
	var removes: Array[Node] = []
	## [code][object, property, value][/code] triples.
	var sets: Array = []

	func is_empty() -> bool:
		return adds.is_empty() and removes.is_empty() and sets.is_empty()

	func add(parent: Node, node: Node) -> Edit:
		adds.append([parent, node])
		return self

	func remove(node: Node) -> Edit:
		if not removes.has(node):
			removes.append(node)
		return self

	func set_value(object: Object, property: StringName, value: Variant) -> Edit:
		sets.append([object, property, value])
		return self

	func merge(other: Edit) -> Edit:
		adds.append_array(other.adds)
		for node in other.removes:
			remove(node)
		sets.append_array(other.sets)
		return self

	## The nodes it adds.
	func added() -> Array[Node]:
		var out: Array[Node] = []
		for pair: Array in adds:
			out.append(pair[1])
		return out

	## Makes the change without undo; added nodes are owned by [param scene_owner].
	func apply(scene_owner: Node) -> void:
		for node in removes:
			node.get_parent().remove_child(node)
			node.free()
		for pair: Array in adds:
			(pair[0] as Node).add_child(pair[1], true)
			MapKitTools.own(pair[1], scene_owner)
		for triple: Array in sets:
			(triple[0] as Object).set(triple[1], triple[2])


## Whether [param map_name] can name a map's folder and scene: lower case letters, digits, and
## underscores, starting with a letter.
static func is_map_name(map_name: String) -> bool:
	var pattern := RegEx.create_from_string("^[a-z][a-z0-9_]*$")
	return pattern.search(map_name) != null


## The scene of the map [param map_name] under [param root].
static func map_path(map_name: String, root := MapCatalogue.ROOT) -> String:
	return root.path_join(map_name).path_join(map_name + ".tscn")


## Creates [code]<root>/<map_name>/<map_name>.tscn[/code], a new inherited scene of the map base
## with its id and title set, and returns its path; empty when the name is not valid or the map
## exists.
static func create_map(map_name: String, title: String, root := MapCatalogue.ROOT) -> String:
	var path := map_path(map_name, root)
	if not is_map_name(map_name) or ResourceLoader.exists(path):
		return ""
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return ""
	# Written as text: an inherited scene keeps only what differs from the base, and the engine
	# offers no call to pack a scene as inheriting another.
	var text := "[gd_scene format=3]\n\n" \
		+ "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"base\"]\n\n" % BASE \
		+ "[node name=\"%s\" instance=ExtResource(\"base\")]\n" % map_name.to_pascal_case() \
		+ "id = &%s\n" % var_to_str(map_name) \
		+ "title = %s\n" % var_to_str(title if not title.is_empty() else map_name.capitalize())
	return path if _write(path, text) else ""


## The scenes under [param users_root] that use the map at [param path]: the scenarios that
## instance it.
static func map_users(path: String, users_root := USERS_ROOT) -> PackedStringArray:
	var out := PackedStringArray()
	var quoted := "\"%s\"" % path
	for scene in _scenes(users_root):
		if FileAccess.get_file_as_string(scene).contains(quoted):
			out.append(scene)
	return out


## Renames the map [param old] to [param new]: its folder, its scene, its root's name and id, and
## the path in every scenario using it. Returns why it could not; empty when it did.
static func rename_map(old: String, new: String, root := MapCatalogue.ROOT,
		users_root := USERS_ROOT) -> String:
	var problem := _check_new_name(old, new, root)
	if not problem.is_empty():
		return problem
	var old_path := map_path(old, root)
	var users := map_users(old_path, users_root)
	var text := FileAccess.get_file_as_string(old_path)
	if DirAccess.rename_absolute(root.path_join(old), root.path_join(new)) != OK:
		return "Could not move the folder %s." % root.path_join(old)
	var moved := root.path_join(new).path_join(old + ".tscn")
	if DirAccess.rename_absolute(moved, map_path(new, root)) != OK:
		return "Could not rename %s." % moved
	text = _set_root_name(text, new.to_pascal_case())
	text = _set_root_field(text, "id", "&" + var_to_str(new))
	if not _write(map_path(new, root), text):
		return "Could not write %s." % map_path(new, root)
	for user in users:
		_write(user, FileAccess.get_file_as_string(user).replace(
			"\"%s\"" % old_path, "\"%s\"" % map_path(new, root)))
	return ""


## Copies the map [param old] as [param new], titled [param title]: a scene of its own, with a new
## uid. Returns why it could not; empty when it did.
static func duplicate_map(old: String, new: String, title: String,
		root := MapCatalogue.ROOT) -> String:
	var problem := _check_new_name(old, new, root)
	if not problem.is_empty():
		return problem
	var text := FileAccess.get_file_as_string(map_path(old, root))
	text = RegEx.create_from_string(" uid=\"uid://[^\"]*\"").sub(text, "", false)
	text = _set_root_name(text, new.to_pascal_case())
	text = _set_root_field(text, "id", "&" + var_to_str(new))
	text = _set_root_field(text, "title",
		var_to_str(title if not title.is_empty() else new.capitalize()))
	if DirAccess.make_dir_recursive_absolute(root.path_join(new)) != OK \
			or not _write(map_path(new, root), text):
		return "Could not write %s." % map_path(new, root)
	return ""


## Deletes the map [param map_name] with its folder, to the system's trash when
## [param to_trash]. A map a scenario uses is kept. Returns why it could not; empty when it did.
static func delete_map(map_name: String, root := MapCatalogue.ROOT, users_root := USERS_ROOT,
		to_trash := true) -> String:
	var path := map_path(map_name, root)
	if not FileAccess.file_exists(path):
		return "There is no map %s." % map_name
	var users := map_users(path, users_root)
	if not users.is_empty():
		return "%s is used by %s." % [map_name, ", ".join(users)]
	var folder := root.path_join(map_name)
	if to_trash:
		return "" if OS.move_to_trash(ProjectSettings.globalize_path(folder)) == OK \
			else "Could not move %s to the trash." % folder
	_remove_tree(folder)
	return "" if not DirAccess.dir_exists_absolute(folder) else "Could not delete %s." % folder


## The palette, in the order the dock lists it.
static func pieces() -> Array[Piece]:
	var out: Array[Piece] = []
	var road := Piece.new("Road", "Roads", "Roads", func() -> Node3D: return _road(false),
		_icon("road"), "A two-way road along a curve; shape it, then generate its lanes.")
	var one_way := Piece.new("One-way road", "Roads", "Roads", func() -> Node3D: return _road(true),
		_icon("one_way_road"), "A road whose lanes all run along its curve.")
	var crossroads := Piece.new("Crossroads", "Roads", "Roads",
		func() -> Node3D: return _junction(RoadJunction.Shape.CROSSROADS), _icon("crossroads"),
		"A junction of four arms.")
	var t_junction := Piece.new("T junction", "Roads", "Roads",
		func() -> Node3D: return _junction(RoadJunction.Shape.T), _icon("t_junction"),
		"A junction of three arms.")
	for piece in [road, one_way, crossroads, t_junction]:
		piece.joins_roads = true
		out.append(piece)
	out.append(Piece.new("Lane", "Lanes and markings", "Lanes", _lane, _icon("lane"),
		"A lane road users drive along, drawn in their direction of travel."))
	var markings := {"Solid line": RoadMarking.Kind.SOLID, "Dashed line": RoadMarking.Kind.DASHED,
		"Double solid line": RoadMarking.Kind.DOUBLE_SOLID, "Stop line": RoadMarking.Kind.STOP_LINE,
		"Give way line": RoadMarking.Kind.GIVE_WAY_LINE, "Zebra": RoadMarking.Kind.ZEBRA,
		"No-parking line": RoadMarking.Kind.NO_PARKING, "Kerb": RoadMarking.Kind.KERB}
	for label: String in markings:
		var kind: int = markings[label]
		out.append(Piece.new(label, "Lanes and markings", "Markings",
			func() -> Node3D: return _marking(kind), _icon("marking"),
			"A %s painted along a curve." % label.to_lower()))
	out.append(Piece.new("Traffic light", "Traffic", "Traffic", _light, _icon("traffic_light"),
		"A light; point lanes at it to make their traffic obey it."))
	out.append(Piece.new("Traffic source", "Traffic", "Traffic", _source, _icon("traffic_source"),
		"Sends road users down its lanes."))
	out.append(Piece.new("Checkpoint", "Traffic", "Traffic", _checkpoint, _icon("checkpoint"),
		"A point road users drive to; pair it with a car under Road users."))
	for kind: int in RoadSign.Kind.values():
		var key: String = RoadSign.Kind.keys()[kind]
		out.append(Piece.new(sentence(key), "Signs", "Signs", func() -> Node3D: return _sign(kind),
			_icon("sign_" + key.to_lower()), "A %s sign; scenery only." % sentence(key).to_lower()))
	var shapes := {"Hill": "A rise in the land, full within its radius, easing out over its falloff.",
		"Valley": "A hollow in the land, full within its radius, easing out over its falloff.",
		"Ramp": "A slope over its rectangle, climbing its height towards -Z.",
		"Plateau": "Flat land at its height within its radius, easing out over its falloff."}
	for label: String in shapes:
		var kind: int = TerrainShape.Kind[label.to_upper()]
		out.append(Piece.new(label, "Terrain", "", func() -> Node3D: return _terrain_shape(kind),
			_icon("terrain_" + label.to_lower()), shapes[label] + " Shapes the map's terrain."))
	out.append(Piece.new("Spawn", "Zones and places", "", _spawn, _icon("spawn"),
		"Where the car may start, facing the arrow."))
	out.append(Piece.new("Trigger zone", "Zones and places", "Zones",
		func() -> Node3D: return _zone(TriggerZone.new(), "TriggerZone"), _icon("zone"),
		"A box that starts lights and road users when the car enters it."))
	out.append(Piece.new("No-parking zone", "Zones and places", "Zones",
		func() -> Node3D: return _zone(NoParkingZone.new(), "NoParkingZone"),
		_icon("no_parking_zone"), "A box the car must not stop in."))
	out.append(Piece.new("Crossing area", "Zones and places", "Zones", _crossing,
		_icon("crossing"), "A pedestrian crossing: its zone, and who walks over it."))
	out.append(Piece.new("Parking bay", "Zones and places", "Zones", _bay, _icon("parking_bay"),
		"A bay the car can park in."))
	return out


## [param key], an enum key such as [code]PARKED_CAR[/code], in sentence case: "Parked car".
static func sentence(key: String) -> String:
	var words := key.to_lower().replace("_", " ")
	return words.left(1).to_upper() + words.substr(1)


## Sets the owner of [param node] and of every descendant that is not internal, so a scene saves
## them.
static func own(node: Node, scene_owner: Node) -> void:
	if node != scene_owner:
		node.owner = scene_owner
	for child in node.get_children():
		own(child, scene_owner)


## The transform from [param node]'s space to [param map]'s, without needing the tree.
static func to_map(node: Node, map: Node) -> Transform3D:
	var out := Transform3D.IDENTITY
	var at := node
	while at != null and at != map:
		if at is Node3D:
			out = (at as Node3D).transform * out
		at = at.get_parent()
	return out


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
## when there is none.
static func nearest_end(map: Node, point: Vector3, reach := SNAP_REACH) -> Dictionary:
	var best := {}
	var best_distance := reach
	for end in road_ends(map):
		var distance: float = end.transform.origin.distance_to(point)
		if distance <= best_distance:
			best = end
			best_distance = distance
	return best


## Where a road or junction [param node] placed at [param point] goes to join the open road end
## nearest it: its transform in the map's space; null when no end is near.
static func joining_transform(map: Node, node: Node3D, point: Vector3) -> Variant:
	var end := nearest_end(map, point)
	if end.is_empty():
		return null
	if node is RoadJunction:
		var junction := node as RoadJunction
		junction.road_width = end.width
		var arm := junction.arm_end(RoadJunction.Arm.SOUTH)
		return _facing_back(end.transform) * arm.affine_inverse()
	if node is RoadSegment:
		var segment := node as RoadSegment
		segment.curve = _straight_from(EXTENSION)
		var lanes := segment.lanes_each_way * (1.0 if segment.one_way else 2.0)
		segment.lane_width = end.width / lanes
		return end.transform
	return null


## Adds a road from the open end of [param road] nearest [param near], with the same lanes:
## [constant EXTENSION] metres straight on. Empty when the road has no open end.
static func extend_road(map: Node, road: Node3D, near := Vector3.INF) -> Edit:
	var end := _end_of(map, road, near)
	if end.is_empty():
		return Edit.new()
	var segment := _road(road is RoadSegment and (road as RoadSegment).one_way)
	segment.curve = _straight_from(EXTENSION)
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
	segment.transform = to_map(parent, map).affine_inverse() * end.transform
	return Edit.new().add(parent, segment)


## Adds a junction of [param shape] on the open end of [param road] nearest [param near], joined
## by its south arm. Empty when the road has no open end.
static func junction_at_end(map: Node, road: Node3D, shape: RoadJunction.Shape,
		near := Vector3.INF) -> Edit:
	var end := _end_of(map, road, near)
	if end.is_empty():
		return Edit.new()
	var junction := _junction(shape) as RoadJunction
	var at: Variant = joining_transform(map, junction, end.transform.origin)
	var parent := road.get_parent()
	junction.transform = to_map(parent, map).affine_inverse() * (at as Transform3D)
	return Edit.new().add(parent, junction)


## Regenerates every road's and junction's lanes, markings, and lines in [param map], and links
## all its lanes whose ends meet.
static func generate_all(map: Node) -> Edit:
	var edit := Edit.new()
	for node in _nodes(map):
		if node is RoadSegment or node is RoadJunction:
			edit.merge(regenerate(node))
	return edit.merge(link_lanes(map, edit))


## Replaces what [param road], a [RoadSegment] or [RoadJunction], generated: its lanes and
## markings, or its lines and lanes.
static func regenerate(road: Node3D) -> Edit:
	var edit := Edit.new()
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
static func link_lanes(map: Node, pending: Edit = null) -> Edit:
	var edit := Edit.new()
	var removed: Array[Node] = []
	if pending:
		removed = pending.removes
	var placed := {}
	var lanes: Array[TrafficLane] = []
	for node in _nodes(map):
		if node is TrafficLane and not removed.has(node) and not _inside(node, removed):
			lanes.append(node)
			placed[node] = to_map(node, map)
	var fresh: Array[TrafficLane] = []
	if pending:
		for pair: Array in pending.adds:
			for node in _with_descendants(pair[1]):
				if node is TrafficLane:
					fresh.append(node)
					placed[node] = to_map(pair[0], map) * to_map(node, pair[1])
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


## Every problem of [param map] and its nodes, as
## [code]{node, message, severity, fix, fix_label}[/code]: the nodes' configuration warnings and
## the kit's own checks, the severity [constant WARNING] or [constant NOTICE], and a fix, an
## [MapKitTools.Edit], where one is known (null otherwise). One entry when [param map] is not a
## [RoadMap].
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
				_fix(entry, "Add spawn", Edit.new().add(map, _spawn_on_road(road_map)))
			elif node is TriggerZone and (node as TriggerZone).box_data() == null:
				_fix(entry, "Add box", Edit.new().add(node, _box(Vector3(4, 3, 4))))
			out.append(entry)
	for node in all:
		if node is RoadSegment:
			var segment := node as RoadSegment
			if segment.generated(RoadSegment.LANES).is_empty() \
					and segment.generated(RoadSegment.MARKINGS).is_empty():
				out.append(_fix(_problem(node, "The road has no lanes or markings yet."),
					"Generate", regenerate(segment)))
	_lane_problems(road_map, out)
	_spawn_problems(road_map, out)
	if Terrain.of(road_map) == null:
		for node in road_map.nodes():
			if node is TerrainShape:
				out.append(_fix(_problem(node, "The map has no terrain for the shape to shape."),
					"Add terrain", add_terrain(road_map)))
				break
	for node in road_map.nodes():
		if node is ScriptedAgent and (node as ScriptedAgent).destination:
			var way := way_of(road_map, node)
			if not way.is_empty() and (not way.reachable or not way.on_lane):
				out.append(_problem(node, "It cannot reach %s along the lanes; link the lanes "
					% (node as ScriptedAgent).destination.name + "on its way, or move the "
					+ "checkpoint onto one."))
	return out


## The lane of [param map] nearest [param place] (in the map's space) that runs the way it faces,
## within [param reach] metres; null when none does.
static func nearest_lane(map: Node, place: Transform3D, reach := 6.0) -> TrafficLane:
	var ahead := -place.basis.z
	ahead.y = 0.0
	var best: TrafficLane = null
	var best_distance := reach
	for node in _nodes(map):
		var lane := node as TrafficLane
		if lane == null or lane.length() <= 0.0:
			continue
		var into := to_map(lane, map)
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
static func drive_to(map: Node, cars: Array, checkpoint: Node3D) -> Edit:
	var edit := Edit.new()
	var parent: Node = map.get_node_or_null("Traffic")
	if parent == null:
		parent = map
	for car: Node in cars:
		if car is ScriptedAgent:
			edit.set_value(car, &"destination", checkpoint)
			continue
		if not (car is MapAsset or car is Prop):
			continue
		var place := to_map(car, map)
		var lane := nearest_lane(map, place)
		if lane == null:
			continue
		var agent := ScriptedAgent.new()
		agent.name = String(car.name) + "Driver"
		agent.transform = to_map(parent, map).affine_inverse() * place
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
## [method LaneRouter.route] gives it; empty when it has no destination or no lane.
static func way_of(map: Node, agent: ScriptedAgent) -> Dictionary:
	if agent.destination == null or not agent.path is TrafficLane:
		return {}
	var lanes := {}
	for node in _nodes(map):
		var lane := node as TrafficLane
		if lane and lane.length() > 0.0:
			lanes[lane.get_instance_id()] = LaneData.of(lane.get_instance_id(), lane.curve,
				to_map(lane, map), {is_lane = true,
					next = PackedInt64Array(lane.next.filter(func(n: TrafficLane) -> bool:
						return n != null).map(func(n: TrafficLane) -> int:
							return n.get_instance_id()))})
	var from: LaneData = lanes.get(agent.path.get_instance_id())
	if from == null:
		return {}
	var start := from.project(to_map(agent, map).origin).x
	return LaneRouter.route(lanes, from.id, start, to_map(agent.destination, map).origin)


## A static body of the obstacle [BodyType] with a box around [param node]'s meshes, local to it; null
## when it has no meshes.
static func obstacle_body(node: Node3D) -> StaticBody3D:
	var bounds := _bounds(node, Transform3D.IDENTITY)
	if bounds == null:
		return null
	var box: AABB = bounds
	var body := StaticBody3D.new()
	body.name = "Obstacle"
	BodyType.of(&"obstacle").apply(body)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var size := BoxShape3D.new()
	size.size = box.size.max(Vector3.ONE * 0.05)
	shape.shape = size
	shape.position = box.get_center()
	body.add_child(shape)
	return body


## [param position] on a grid of [param step] metres, its height kept.
static func snapped(position: Vector3, step := 0.5) -> Vector3:
	if step <= 0.0:
		return position
	return Vector3(snappedf(position.x, step), position.y, snappedf(position.z, step))


## Whether [param point], in the map's space, lies on one of [param map]'s roads or junctions.
static func on_road(map: Node, point: Vector3) -> bool:
	for node in _nodes(map):
		if node is RoadSegment:
			var segment := node as RoadSegment
			var into := to_map(segment, map)
			var reach := sqrt(pow(segment.width() / 2.0, 2) + pow(RoadSegment.STEP / 2.0, 2)) + 0.25
			for frame: Array in segment.frames():
				var at: Vector3 = into * frame[0]
				if Vector2(at.x - point.x, at.z - point.z).length() <= reach:
					return true
		elif node is RoadJunction:
			var junction := node as RoadJunction
			var local := to_map(junction, map).affine_inverse() * point
			var half := junction.road_width / 2.0
			var reach := half + junction.arm_length
			if (absf(local.x) <= half and absf(local.z) <= reach) \
					or (absf(local.z) <= half and absf(local.x) <= reach):
				return true
	return false


## Adds a [Terrain] to [param map] over its environment's ground, whose flat ground it turns off.
## Empty when the map has a terrain already.
static func add_terrain(map: Node) -> Edit:
	var edit := Edit.new()
	if map == null or Terrain.of(map) != null:
		return edit
	var terrain := Terrain.new()
	terrain.name = "Terrain"
	for node in _nodes(map):
		if node is RoadEnvironment:
			var environment := node as RoadEnvironment
			terrain.size = environment.ground_size
			terrain.position = to_map(environment, map) * environment.ground_offset
			if environment.ground:
				edit.set_value(environment, &"ground", false)
	edit.add(map, terrain)
	return edit


## Sets the heights of [param nodes] and everything under them (all of [param map]'s when empty)
## from the map's [Terrain], without its roads: a road's curve, redrawn a point every
## [constant RoadSegment.STEP] metres, follows the land smoothed to no steeper than
## [param max_grade] (rise over run), its ends held at the junctions they join; a junction stands
## on the land at its centre; lanes and markings, redrawn the same way, lie on the road or junction
## under them or else on the land; spawns, props, assets, signs, lights, and checkpoints stand on
## the same. Empty when the map has no terrain.
static func drape(map: Node, nodes: Array = [], max_grade := 0.12) -> Edit:
	var edit := Edit.new()
	var terrain := Terrain.of(map)
	if terrain == null:
		return edit
	var land := terrain.land()
	var picked: Array[Node] = []
	for node: Node in (nodes if not nodes.is_empty() else _nodes(map)):
		for inner in _with_descendants(node):
			if not picked.has(inner):
				picked.append(inner)
	# The junctions first: the roads' ends are held at their heights.
	var junction_y := {}
	for node in _nodes(map):
		if node is RoadJunction:
			var junction := node as RoadJunction
			var placed := to_map(junction, map)
			if picked.has(junction):
				placed.origin.y = terrain.land_height_at(placed.origin, land)
				edit.set_value(junction, &"position", (to_map(junction.get_parent(), map)
					.affine_inverse() * placed).origin)
			junction_y[junction] = placed
	# Every road's centre line in the map's space, as it will be.
	var lines: Array = []
	for node in _nodes(map):
		if not node is RoadSegment:
			continue
		var road := node as RoadSegment
		var into := to_map(road, map)
		var reach := road.width() / 2.0 + (road.pavement if road.kerbs else 0.0)
		if not picked.has(road):
			var points := PackedVector3Array()
			for frame: Array in road.frames():
				points.append(into * (frame[0] as Vector3))
			lines.append([points, reach])
			continue
		var points := _resampled(road.curve, RoadSegment.STEP, into)
		if points.size() < 2:
			continue
		var heights := PackedFloat32Array()
		for point in points:
			heights.append(terrain.land_height_at(point, land))
		var pins := {}
		for end: int in [0, points.size() - 1]:
			var held: Variant = _junction_height(points[end], junction_y)
			if held != null:
				pins[end] = held
		heights = graded(points, heights, max_grade, pins)
		var curve := Curve3D.new()
		var back := into.affine_inverse()
		for i in points.size():
			points[i].y = heights[i]
			curve.add_point(back * points[i])
		edit.set_value(road, &"curve", curve)
		lines.append([points, reach])
	var surface := func(point: Vector3) -> float:
		return _surface_height(point, junction_y, lines, terrain, land)
	for node in picked:
		if node is TrafficLane or node is RoadMarking:
			var path := node as Path3D
			if path.curve == null or path.curve.point_count < 2:
				continue
			var into := to_map(path, map)
			var points := _resampled(path.curve, RoadSegment.STEP, into)
			var curve := Curve3D.new()
			var back := into.affine_inverse()
			for point in points:
				point.y = surface.call(point)
				curve.add_point(back * point)
			edit.set_value(path, &"curve", curve)
		elif node is MapSpawn or node is Prop or node is MapAsset or node is RoadSign \
				or node is Scenery or node is TrafficLight or node is Checkpoint:
			var placed := to_map(node, map)
			placed.origin.y = surface.call(placed.origin)
			edit.set_value(node, &"position", (to_map(node.get_parent(), map).affine_inverse()
				* placed).origin)
	return edit


## [param heights] along [param points] (the same count) made no steeper than [param grade] between
## neighbours, measured across the ground: halfway between the highest and the lowest such
## profiles under and over the heights, then held at [param pins] (index to height) and eased away
## from them.
static func graded(points: PackedVector3Array, heights: PackedFloat32Array, grade: float,
		pins := {}) -> PackedFloat32Array:
	var n := heights.size()
	var rise := PackedFloat32Array()
	for i in n - 1:
		rise.append(grade * Vector2(points[i + 1].x - points[i].x,
			points[i + 1].z - points[i].z).length())
	var low := heights.duplicate()
	var high := heights.duplicate()
	for i in range(1, n):
		low[i] = minf(low[i], low[i - 1] + rise[i - 1])
		high[i] = maxf(high[i], high[i - 1] - rise[i - 1])
	for i in range(n - 2, -1, -1):
		low[i] = minf(low[i], low[i + 1] + rise[i])
		high[i] = maxf(high[i], high[i + 1] - rise[i])
	var out := PackedFloat32Array()
	for i in n:
		out.append((low[i] + high[i]) * 0.5)
	if pins.has(0):
		out[0] = pins[0]
		for i in range(1, n):
			out[i] = clampf(out[i], out[i - 1] - rise[i - 1], out[i - 1] + rise[i - 1])
	if pins.has(n - 1):
		out[n - 1] = pins[n - 1]
		for i in range(n - 2, -1, -1):
			out[i] = clampf(out[i], out[i + 1] - rise[i], out[i + 1] + rise[i])
	return out


## [param curve]'s points, every [param step] metres or a little less and at both ends, taken by
## [param into].
static func _resampled(curve: Curve3D, step: float, into: Transform3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	if curve == null or curve.point_count < 2:
		return out
	var length := curve.get_baked_length()
	var count := maxi(ceili(length / step - 0.001), 1)
	for k in count + 1:
		out.append(into * curve.sample_baked(length * k / count))
	return out


## The height of the junction arm end [param point] meets, from [param junction_y] (junction to its
## transform in the map's space); null when it meets none.
static func _junction_height(point: Vector3, junction_y: Dictionary) -> Variant:
	for junction: RoadJunction in junction_y:
		var placed: Transform3D = junction_y[junction]
		for arm in junction.arms():
			var end := placed * junction.arm_end(arm).origin
			if Vector2(end.x - point.x, end.z - point.z).length() <= JOIN:
				return placed.origin.y
	return null


## The height of what stands under [param point]: a junction's pad, a road's centre line within
## its reach across, or else the land.
static func _surface_height(point: Vector3, junction_y: Dictionary, lines: Array,
		terrain: Terrain, land: HeightField) -> float:
	for junction: RoadJunction in junction_y:
		var placed: Transform3D = junction_y[junction]
		var local := placed.affine_inverse() * point
		var half := junction.road_width / 2.0 + RoadKit.PAVEMENT
		var reach := junction.road_width / 2.0 + junction.arm_length
		if (absf(local.x) <= half and absf(local.z) <= reach) \
				or (absf(local.z) <= half and absf(local.x) <= reach):
			return placed.origin.y
	var best := INF
	var best_y := 0.0
	var at := Vector2(point.x, point.z)
	for line: Array in lines:
		var points: PackedVector3Array = line[0]
		for i in points.size() - 1:
			var a := Vector2(points[i].x, points[i].z)
			var d := Vector2(points[i + 1].x, points[i + 1].z) - a
			var t := clampf((at - a).dot(d) / d.length_squared(), 0.0, 1.0) \
				if d.length_squared() > 0.0 else 0.0
			var off := at.distance_to(a + d * t)
			if off <= float(line[1]) and off < best:
				best = off
				best_y = lerpf(points[i].y, points[i + 1].y, t)
	if best < INF:
		return best_y
	return terrain.land_height_at(point, land)


static func _lane_problems(map: RoadMap, out: Array[Dictionary]) -> void:
	var lanes: Array = []
	var placed := {}
	for node in map.nodes():
		if node is TrafficLane and (node as TrafficLane).length() > 0.0:
			lanes.append(node)
			placed[node] = to_map(node, map)
	var links := lane_links(lanes, 1.0, placed)
	for lane: TrafficLane in lanes:
		if links.has(lane):
			var next: Array[TrafficLane] = lane.next.duplicate()
			next.append_array(links[lane])
			var names := ", ".join(links[lane].map(func(l: TrafficLane) -> String: return l.name))
			var message := "The lane ends where %s starts but is not linked." % names
			out.append(_fix(_problem(lane, message), "Connect",
				Edit.new().set_value(lane, &"next", next)))
		elif lane.next.is_empty():
			out.append(_problem(lane, "The lane leads nowhere; road users leave the map there.",
				NOTICE))


static func _spawn_problems(map: RoadMap, out: Array[Dictionary]) -> void:
	var spawns := map.spawns()
	for i in spawns.size():
		var at := to_map(spawns[i], map).origin
		if not on_road(map, at) and _has_roads(map):
			out.append(_problem(spawns[i], "The spawn is not on a road.", NOTICE))
		for j in range(i + 1, spawns.size()):
			if at.distance_to(to_map(spawns[j], map).origin) < 2.0:
				out.append(_problem(spawns[j], "The spawn overlaps %s." % spawns[i].name, NOTICE))


static func _has_roads(map: Node) -> bool:
	return _nodes(map).any(func(n: Node) -> bool: return n is RoadSegment or n is RoadJunction)


static func _problem(node: Node, message: String, severity := WARNING) -> Dictionary:
	return {node = node, message = message, severity = severity, fix = null, fix_label = ""}


static func _fix(entry: Dictionary, label: String, edit: Edit) -> Dictionary:
	if not edit.is_empty():
		entry.fix = edit
		entry.fix_label = label
	return entry


## A spawn on the map's first lane, two metres in, facing along it; at the origin without lanes.
static func _spawn_on_road(map: RoadMap) -> MapSpawn:
	var spawn := _spawn() as MapSpawn
	for node in map.nodes():
		if node is TrafficLane and (node as TrafficLane).length() > 4.0:
			var lane := node as TrafficLane
			var into := to_map(lane, map)
			var at := into * lane.curve.sample_baked(2.0)
			var ahead := into * lane.curve.sample_baked(3.0) - at
			ahead.y = 0.0
			spawn.transform = Transform3D(Basis.looking_at(ahead.normalized()), at)
			break
	return spawn


static func _all_road_ends(map: Node) -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	for node in _nodes(map):
		if node is RoadSegment:
			var segment := node as RoadSegment
			var into := to_map(segment, map)
			for end in segment.ends():
				all.append({transform = into * end, width = segment.width(), node = segment})
		elif node is RoadJunction:
			var junction := node as RoadJunction
			var into := to_map(junction, map)
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


static func _nodes(map: Node) -> Array[Node]:
	if map is RoadMap:
		return (map as RoadMap).nodes()
	var out: Array[Node] = []
	Scenario.collect(map, out)
	return out


static func _with_descendants(node: Node) -> Array[Node]:
	var out: Array[Node] = [node]
	for child in node.get_children():
		out.append_array(_with_descendants(child))
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


static func _check_new_name(old: String, new: String, root: String) -> String:
	if not FileAccess.file_exists(map_path(old, root)):
		return "There is no map %s." % old
	if not is_map_name(new):
		return "Name the map with lower case letters, digits, and underscores, starting with a " \
			+ "letter."
	if DirAccess.dir_exists_absolute(root.path_join(new)):
		return "A map %s exists already." % new
	return ""


## [param text], a scene, with its root node named [param root_name].
static func _set_root_name(text: String, root_name: String) -> String:
	var pattern := RegEx.create_from_string("(?m)^\\[node name=\"[^\"]*\"")
	return pattern.sub(text, "[node name=\"%s\"" % root_name, false)


## [param text], a scene, with the root node's [param key] set to [param value], written as it
## is in a scene file.
static func _set_root_field(text: String, key: String, value: String) -> String:
	var lines := text.split("\n")
	var root := -1
	for i in lines.size():
		if lines[i].begins_with("[node "):
			root = i
			break
	if root < 0:
		return text
	var end := lines.size()
	for i in range(root + 1, lines.size()):
		if lines[i].begins_with("["):
			end = i
			break
	for i in range(root + 1, end):
		if lines[i].begins_with(key + " = "):
			lines[i] = "%s = %s" % [key, value]
			return "\n".join(lines)
	lines.insert(root + 1, "%s = %s" % [key, value])
	return "\n".join(lines)


static func _scenes(folder: String) -> PackedStringArray:
	var out := PackedStringArray()
	for file in DirAccess.get_files_at(folder):
		if file.ends_with(".tscn"):
			out.append(folder.path_join(file))
	for sub in DirAccess.get_directories_at(folder):
		out.append_array(_scenes(folder.path_join(sub)))
	return out


static func _write(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true


static func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for folder in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(folder))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)


static func _icon(icon_name: String) -> String:
	return ICONS + icon_name + ".svg"


static func _bounds(node: Node, to_root: Transform3D) -> Variant:
	var out: Variant = null
	var here := to_root
	if node is VisualInstance3D:
		var box: AABB = here * (node as VisualInstance3D).get_aabb()
		out = box
	for child in node.get_children(true):
		var child_transform := here * (child as Node3D).transform if child is Node3D else here
		var inner: Variant = _bounds(child, child_transform)
		if inner != null:
			out = inner if out == null else (out as AABB).merge(inner)
	return out


static func _straight(length: float) -> Curve3D:
	var curve := Curve3D.new()
	curve.add_point(Vector3(0, 0, length / 2.0))
	curve.add_point(Vector3(0, 0, -length / 2.0))
	return curve


## A straight curve from the origin along -Z.
static func _straight_from(length: float) -> Curve3D:
	var curve := Curve3D.new()
	curve.add_point(Vector3.ZERO)
	curve.add_point(Vector3(0, 0, -length))
	return curve


static func _road(one_way: bool) -> RoadSegment:
	var road := RoadSegment.new()
	road.name = "OneWayRoad" if one_way else "Road"
	road.one_way = one_way
	road.curve = _straight(20.0)
	return road


static func _junction(shape: RoadJunction.Shape) -> Node3D:
	var junction := RoadJunction.new()
	junction.name = "Crossroads" if shape == RoadJunction.Shape.CROSSROADS else "TJunction"
	junction.shape = shape
	return junction


static func _lane() -> Node3D:
	var lane := TrafficLane.new()
	lane.name = "Lane"
	lane.curve = _straight(20.0)
	return lane


static func _marking(kind: RoadMarking.Kind) -> Node3D:
	var marking := RoadMarking.new()
	marking.name = String(RoadMarking.Kind.keys()[kind]).to_pascal_case()
	marking.kind = kind
	if kind in [RoadMarking.Kind.STOP_LINE, RoadMarking.Kind.GIVE_WAY_LINE, RoadMarking.Kind.ZEBRA]:
		marking.curve = Curve3D.new()
		marking.curve.add_point(Vector3(-1.75, 0, 0))
		marking.curve.add_point(Vector3(1.75, 0, 0))
		marking.width = 3.0 if kind == RoadMarking.Kind.ZEBRA else 0.3
	else:
		marking.curve = _straight(20.0)
	return marking


static func _terrain_shape(kind: TerrainShape.Kind) -> Node3D:
	var shape := TerrainShape.new()
	shape.name = String(TerrainShape.Kind.keys()[kind]).to_pascal_case()
	shape.kind = kind
	return shape


static func _light() -> Node3D:
	var light := TrafficLight.new()
	light.name = "TrafficLight"
	return light


static func _source() -> Node3D:
	var source := TrafficSource.new()
	source.name = "TrafficSource"
	return source


static func _sign(kind: RoadSign.Kind) -> Node3D:
	var road_sign := RoadSign.new()
	road_sign.name = String(RoadSign.Kind.keys()[kind]).to_pascal_case() + "Sign"
	road_sign.kind = kind
	return road_sign


## Every prop, scenery, and map asset of [param nodes] with its next look: the next variant of a
## prop with several, the next kind of scenery, the next model of a map asset's category.
static func next_look(nodes: Array) -> Edit:
	var edit := Edit.new()
	var entries: Array[AssetCatalogue.Entry] = []
	for node: Node in nodes:
		if node is Prop and (node as Prop).preset in [Prop.Preset.PARKED_CAR, Prop.Preset.VAN,
				Prop.Preset.BUILDING]:
			edit.set_value(node, &"variant", (node as Prop).variant + 1)
		elif node is Scenery:
			edit.set_value(node, &"kind",
				posmod((node as Scenery).kind + 1, Scenery.Kind.size()))
		elif node is MapAsset:
			if entries.is_empty():
				entries = AssetCatalogue.scan()
			var next := next_asset((node as MapAsset).model, entries)
			if next:
				set_model(edit, node as MapAsset, next)
	return edit


## Gives [param asset] the model of [param entry], set up as its category says, in [param edit].
static func set_model(edit: Edit, asset: MapAsset, entry: AssetCatalogue.Entry) -> void:
	var template := AssetCatalogue.make(entry)
	for property in MapAsset.SETTINGS:
		edit.set_value(asset, property, template.get(property))
	template.free()


## The model after [param model_path] in its category and pack of [param entries] (the
## [AssetCatalogue]'s scan), wrapping round; null when it is not listed.
static func next_asset(model_path: String,
		entries: Array[AssetCatalogue.Entry]) -> AssetCatalogue.Entry:
	var at := -1
	for i in entries.size():
		if entries[i].path == model_path:
			at = i
	if at < 0:
		return null
	var same := entries.filter(func(e: AssetCatalogue.Entry) -> bool:
		return e.category == entries[at].category and e.pack == entries[at].pack)
	return same[(same.find(entries[at]) + 1) % same.size()]


static func _checkpoint() -> Node3D:
	var checkpoint := Checkpoint.new()
	checkpoint.name = "Checkpoint"
	return checkpoint


static func _spawn() -> Node3D:
	var spawn := MapSpawn.new()
	spawn.name = "Spawn"
	return spawn


static func _zone(zone: TriggerZone, zone_name: String) -> Node3D:
	zone.name = zone_name
	zone.position.y = 1.5
	zone.add_child(_box(Vector3(4, 3, 4)))
	return zone


static func _box(size: Vector3) -> CollisionShape3D:
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	return shape


static func _crossing() -> Node3D:
	var crossing := Crossing.new()
	crossing.name = "Crossing"
	var zone := _zone(TriggerZone.new(), "Zone") as TriggerZone
	(zone.get_child(0) as CollisionShape3D).shape.size = Vector3(7, 3, 3)
	crossing.add_child(zone)
	crossing.zone = zone
	return crossing


static func _bay() -> Node3D:
	var bay := ParkingBay.new()
	bay.name = "ParkingBay"
	return bay
