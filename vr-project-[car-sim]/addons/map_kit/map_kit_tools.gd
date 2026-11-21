@tool
class_name MapKitTools
extends RefCounted
## What the Map Kit editor plugin does to a map, kept apart from the editor so it runs and is
## tested headless: creating a map from the base, building palette pieces, linking lanes whose
## ends meet, giving a mesh a solid body, and listing a map's problems. The plugin adds undo and
## the editor around these.

const BASE := "res://scenarios/kit/map_base.tscn"
const ASPHALT := preload("res://scenarios/kit/asphalt.tres")

## One entry of the palette: its button text, the section it is listed under, the map node it is
## added under, and the function building it.
class Piece:
	extends RefCounted
	var label: String
	var section: String
	var group: String
	var make: Callable

	func _init(p_label: String, p_section: String, p_group: String, p_make: Callable) -> void:
		label = p_label
		section = p_section
		group = p_group
		make = p_make


## Whether [param map_name] can name a map's folder and scene: lower case letters, digits, and
## underscores, starting with a letter.
static func is_map_name(map_name: String) -> bool:
	var pattern := RegEx.create_from_string("^[a-z][a-z0-9_]*$")
	return pattern.search(map_name) != null


## Creates [code]<root>/<map_name>/<map_name>.tscn[/code], a new inherited scene of the map base
## with its id and title set, and returns its path; empty when the name is not valid or the map
## exists.
static func create_map(map_name: String, title: String, root := MapCatalogue.ROOT) -> String:
	var path := root.path_join(map_name).path_join(map_name + ".tscn")
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
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return ""
	file.store_string(text)
	file.close()
	return path


## The palette, in the order the dock lists it.
static func pieces() -> Array[Piece]:
	var out: Array[Piece] = []
	out.append(Piece.new("Road", "Roads", "Roads", func() -> Node3D: return _road(false)))
	out.append(Piece.new("One-way road", "Roads", "Roads", func() -> Node3D: return _road(true)))
	out.append(Piece.new("Crossroads", "Roads", "Roads",
		func() -> Node3D: return _junction(RoadJunction.Shape.CROSSROADS)))
	out.append(Piece.new("T junction", "Roads", "Roads",
		func() -> Node3D: return _junction(RoadJunction.Shape.T)))
	out.append(Piece.new("Lane", "Lanes and markings", "Lanes", _lane))
	var markings := {"Solid line": RoadMarking.Kind.SOLID, "Dashed line": RoadMarking.Kind.DASHED,
		"Double solid line": RoadMarking.Kind.DOUBLE_SOLID, "Stop line": RoadMarking.Kind.STOP_LINE,
		"Give way line": RoadMarking.Kind.GIVE_WAY_LINE, "Zebra": RoadMarking.Kind.ZEBRA,
		"No-parking line": RoadMarking.Kind.NO_PARKING, "Kerb": RoadMarking.Kind.KERB}
	for label: String in markings:
		var kind: int = markings[label]
		out.append(Piece.new(label, "Lanes and markings", "Markings",
			func() -> Node3D: return _marking(kind)))
	out.append(Piece.new("Traffic light", "Traffic", "Traffic", _light))
	out.append(Piece.new("Traffic source", "Traffic", "Traffic", _source))
	for kind: int in RoadSign.Kind.values():
		out.append(Piece.new(RoadSign.Kind.keys()[kind].capitalize(), "Signs", "Signs",
			func() -> Node3D: return _sign(kind)))
	for preset: int in Prop.Preset.values():
		out.append(Piece.new(Prop.Preset.keys()[preset].capitalize(), "Props", "Props",
			func() -> Node3D: return _prop(preset)))
	out.append(Piece.new("Spawn", "Zones and places", "", _spawn))
	out.append(Piece.new("Trigger zone", "Zones and places", "Zones",
		func() -> Node3D: return _zone(TriggerZone.new(), "TriggerZone")))
	out.append(Piece.new("No-parking zone", "Zones and places", "Zones",
		func() -> Node3D: return _zone(NoParkingZone.new(), "NoParkingZone")))
	out.append(Piece.new("Pedestrian crossing", "Zones and places", "Zones", _crossing))
	out.append(Piece.new("Parking bay", "Zones and places", "Zones", _bay))
	return out


## Sets the owner of [param node] and of every descendant that is not internal, so a scene saves
## them.
static func own(node: Node, scene_owner: Node) -> void:
	if node != scene_owner:
		node.owner = scene_owner
	for child in node.get_children():
		own(child, scene_owner)


## The lanes each of [param lanes] continues onto and does not list yet: every other lane whose
## start lies within [param gap] metres of its end, heading on the same way.
static func lane_links(lanes: Array, gap := 1.0) -> Dictionary:
	var links := {}
	for a: TrafficLane in lanes:
		if a.curve == null or a.length() <= 0.0:
			continue
		var end := a.point_at(a.length())
		var heading := end - a.point_at(a.length() - 0.5)
		for b: TrafficLane in lanes:
			if b == a or b.curve == null or b.length() <= 0.0 or a.next.has(b):
				continue
			var start := b.point_at(0.0)
			var onward := b.point_at(0.5) - start
			var aligned := heading.normalized().dot(onward.normalized()) > 0.5
			if start.distance_to(end) <= gap and aligned:
				if not links.has(a):
					links[a] = [] as Array[TrafficLane]
				links[a].append(b)
	return links


## A static body on the obstacle layer with a box around [param node]'s meshes, local to it; null
## when it has no meshes.
static func obstacle_body(node: Node3D) -> StaticBody3D:
	var bounds := _bounds(node, Transform3D.IDENTITY)
	if bounds == null:
		return null
	var box: AABB = bounds
	var body := StaticBody3D.new()
	body.name = "Obstacle"
	body.collision_layer = Layers.OBSTACLE
	body.collision_mask = 0
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
	return Vector3(snappedf(position.x, step), position.y, snappedf(position.z, step))


## Every configuration warning of [param map] and its nodes, as
## [code]{node, message}[/code]; one entry when [param map] is not a [RoadMap].
static func problems(map: Node) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if not map is RoadMap:
		out.append({node = map, message = "Open a map scene: its root needs to be a RoadMap."})
		return out
	var all: Array[Node] = [map]
	all.append_array((map as RoadMap).nodes())
	for node in all:
		if node.has_method(&"_get_configuration_warnings"):
			for message: String in node.call(&"_get_configuration_warnings"):
				out.append({node = node, message = message})
	return out


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


static func _road(one_way: bool) -> Node3D:
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


static func _prop(preset: Prop.Preset) -> Node3D:
	var prop := Prop.new()
	prop.name = String(Prop.Preset.keys()[preset]).to_pascal_case()
	prop.preset = preset
	return prop


static func _spawn() -> Node3D:
	var spawn := MapSpawn.new()
	spawn.name = "Spawn"
	return spawn


static func _zone(zone: TriggerZone, zone_name: String) -> Node3D:
	zone.name = zone_name
	zone.position.y = 1.5
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = Vector3(4, 3, 4)
	shape.shape = box
	zone.add_child(shape)
	return zone


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
