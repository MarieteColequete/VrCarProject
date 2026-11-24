extends TestCase
## The Map Kit's helpers: creating, renaming, duplicating, and deleting maps, the palette,
## linking lanes, road ends, extending roads, generating a whole map, solid bodies, loose models
## made into map assets, solid things in road users' way, snapping, and a map's problems and their
## fixes.

const ROOT := "user://map_kit_test/"


func run() -> void:
	_test_create_map()
	_test_palette()
	_test_lane_links()
	_test_obstacle_body()
	_test_loose_models()
	_test_in_the_way()
	_test_problems()
	_test_map_files()
	_test_road_ends()
	_test_extend()
	_test_generate_all()
	_test_fixes()
	_test_joining()
	_test_overlay_marks()
	expect(MapKitTools.snapped(Vector3(1.26, 0.3, -0.74)).is_equal_approx(Vector3(1.5, 0.3, -0.5)),
		"snapping keeps the height and rounds to half a metre")


func _test_create_map() -> void:
	_remove(ROOT)
	expect(not MapFiles.is_map_name("Main Street") and not MapFiles.is_map_name("1st")
		and MapFiles.is_map_name("main_street_2"), "map names are lower case folder names")
	var file_path := MapFiles.create_map("main_street", "Main Street", ROOT)
	var entries := MapCatalogue.scan(ROOT)
	expect(file_path == ROOT + "main_street/main_street.tscn" and entries.size() == 1
		and entries[0].id == &"main_street" and entries[0].title == "Main Street",
		"a new map is a folder and scene the scan finds, with its id and title")
	var road_map := load(file_path).instantiate() as RoadMap if not file_path.is_empty() else null
	expect(road_map != null and road_map.has_node("Environment") and road_map.spawns().size() == 1
		and (load(file_path) as PackedScene).get_state().get_node_instance(0) != null,
		"a new map inherits the map base, with its environment and spawn")
	if road_map:
		road_map.free()
	expect(MapFiles.create_map("main_street", "", ROOT).is_empty(),
		"an existing map is not overwritten")
	_remove(ROOT)


func _test_palette() -> void:
	var road_map: RoadMap = load(MapFiles.BASE).instantiate()
	root.add_child(road_map)
	var problems := PackedStringArray()
	var labels := {}
	for piece in MapPalette.pieces():
		if labels.has(piece.label):
			problems.append("%s is listed twice" % piece.label)
		labels[piece.label] = true
		var node: Node3D = piece.make.call()
		if node == null:
			problems.append("%s builds nothing" % piece.label)
			continue
		if not piece.group.is_empty() and not road_map.has_node(piece.group):
			problems.append("%s goes under %s, which the base lacks" % [piece.label, piece.group])
		road_map.add_child(node)
		MapKitTools.own(node, road_map)
		if piece.label != MapPalette.sentence(piece.label.to_upper().replace(" ", "_")) \
				and not piece.label.contains("-"):
			problems.append("%s is not in sentence case" % piece.label)
		if piece.icon.is_empty() or piece.tip.is_empty():
			problems.append("%s has no icon or tooltip" % piece.label)
	# Every piece stands at the origin, where the palette's own lanes run, so solid pieces are in
	# their way there.
	for problem in MapProblems.problems(road_map):
		if problem.node is TrafficLight or problem.node is TrafficSource \
				or problem.severity == MapProblems.NOTICE or problem.fix != null \
				or problem.message.contains("in the way"):
			continue
		problems.append("%s: %s" % [problem.node.name, problem.message])
	expect(problems.is_empty(), "every palette piece builds, ready to use %s" % [problems])
	var packed := PackedScene.new()
	expect(packed.pack(road_map) == OK, "a map of every palette piece packs into a scene")
	road_map.free()


func _lane(from: Vector3, to: Vector3) -> TrafficLane:
	var lane := TrafficLane.new()
	lane.curve = Curve3D.new()
	lane.curve.add_point(from)
	lane.curve.add_point(to)
	root.add_child(lane)
	return lane


func _test_lane_links() -> void:
	var a := _lane(Vector3(0, 0, 10), Vector3(0, 0, 0))
	var b := _lane(Vector3(0.3, 0, -0.2), Vector3(0, 0, -10))
	var back := _lane(Vector3(0, 0, 0), Vector3(0, 0, 10))
	var far := _lane(Vector3(5, 0, 0), Vector3(5, 0, -10))
	var links := RoadNetwork.lane_links([a, b, back, far])
	expect(links.size() == 1 and links.has(a) and links[a] == [b],
		"a lane links to the lane starting where it ends and heading on, not back or far away")
	a.next = [b]
	expect(RoadNetwork.lane_links([a, b, back, far]).is_empty(), "a link already made is not repeated")
	a.next = []
	var joined := RoadNetwork.connect_lanes(null, [a, b, back, far])
	joined.apply(root)
	expect(a.next == [b] and joined.sets.size() == 1,
		"connecting the picked lanes links the ones whose ends meet, as the dock does")
	for lane in [a, b, back, far]:
		lane.free()
	var mesh := MeshInstance3D.new()
	var empty := Node3D.new()
	empty.position = Vector3(1.26, 0.3, -0.74)
	var picked: Array = [mesh, empty]
	AssetTools.set_as_road(picked).apply(root)
	MapKitTools.snap_nodes(picked, 0.5).apply(root)
	expect(mesh.material_override == MapKitTools.ASPHALT
		and empty.position.is_equal_approx(Vector3(1.5, 0.3, -0.5)),
		"setting as road gives the meshes asphalt; snapping moves the nodes onto the grid")
	var road_map := RoadMap.new()
	var one := Checkpoint.new()
	road_map.add_child(one)
	var car := Node3D.new()
	expect(RoadNetwork.checkpoint_for(road_map, [car]) == one
		and RoadNetwork.checkpoint_for(road_map, [car, one]) == one,
		"cars drive to the checkpoint picked with them, else the map's only one")
	road_map.add_child(Checkpoint.new())
	expect(RoadNetwork.checkpoint_for(road_map, [car]) == null,
		"and to none when the map has two and none is picked")
	for node: Node in [mesh, empty, car, road_map]:
		node.free()


func _test_obstacle_body() -> void:
	var holder := Node3D.new()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2, 1, 4)
	mesh.mesh = box
	mesh.position = Vector3(0, 0.5, 1)
	holder.add_child(mesh)
	var body := AssetTools.obstacle_body(holder)
	var shape := body.get_child(0) as CollisionShape3D if body else null
	expect(body != null and body.collision_layer == Layers.OBSTACLE
		and shape.shape.size.is_equal_approx(Vector3(2, 1, 4))
		and shape.position.is_equal_approx(Vector3(0, 0.5, 1)),
		"a solid body boxes the node's meshes on the obstacle layer")
	expect(AssetTools.obstacle_body(Node3D.new()) == null, "a node with no mesh gets no body")
	if body:
		body.free()
	holder.free()


func _test_loose_models() -> void:
	var road_map := RoadMap.new()
	var group := Node3D.new()
	group.name = "Props"
	road_map.add_child(group)
	var house_path := KitModels.building(0)
	var tree_path := KitModels.suburban("tree-large")
	var house := (load(house_path) as PackedScene).instantiate() as Node3D
	house.name = "House"
	house.transform = Transform3D(Basis(Vector3.UP, 0.7).scaled(Vector3.ONE * 2.5), Vector3(12, 0, -5))
	group.add_child(house)
	var tree := (load(tree_path) as PackedScene).instantiate() as Node3D
	tree.name = "Tree"
	tree.transform = Transform3D(Basis.from_scale(Vector3(3, 5, 3)), Vector3(-8, 0, 4))
	group.add_child(tree)
	var empty := MeshInstance3D.new()
	empty.name = "Empty"
	group.add_child(empty)
	root.add_child(road_map)
	var models: Array[Node3D] = [house, tree]
	expect(AssetTools.loose_models([road_map]) == models,
		"the loose models are found, their own parts left out")
	var found := MapProblems.problems(road_map)
	var loose := found.filter(func(p: Dictionary) -> bool: return p.fix_label == "Make map asset")
	var nothing := found.filter(func(p: Dictionary) -> bool: return p.node == empty)
	expect(loose.size() == 2 and nothing.size() == 1 and nothing[0].severity == MapProblems.NOTICE
		and nothing[0].fix_label == "Delete",
		"each loose model is a problem with its fix, and an empty mesh a notice to delete")
	var was := {house = house.transform, tree = tree.transform}
	var edit := AssetTools.make_map_assets([road_map])
	edit.apply(road_map)
	var made_house := group.get_node_or_null("House") as MapAsset
	var made_tree := group.get_node_or_null("Tree") as MapAsset
	expect(made_house != null and made_tree != null and made_house.model == house_path
		and made_tree.model == tree_path, "each becomes a map asset of its model, keeping its name")
	if made_house and made_tree:
		for pair: Array in [[made_house, was.house], [made_tree, was.tree]]:
			var asset: MapAsset = pair[0]
			var drawn := asset.transform * Transform3D(Basis.from_scale(asset.model_scale()),
				Vector3.ZERO) * KitModels.fitting(asset.model)
			expect(drawn.is_equal_approx(pair[1]),
				"%s is drawn where, as turned, and as big as it was" % asset.name)
		# The pack's own scale is in the fitting, so the asset's scale is the model's over it.
		var house_pack := KitModels.fitting(house_path).basis.get_scale().x
		var tree_pack := KitModels.fitting(tree_path).basis.get_scale().x
		expect(made_house.fit == Vector3.ZERO
			and is_equal_approx(made_house.extra_scale, 2.5 / house_pack)
			and made_tree.fit.is_equal_approx(Vector3(3, 5, 3) / tree_pack
				* KitModels.size_of(tree_path)),
			"an even scale stays a scale, an uneven one a fit")
		expect(not made_house.bodies().is_empty(),
			"and it is solid as its category says, so the car hits it")
	found = MapProblems.problems(road_map)
	expect(not found.any(func(p: Dictionary) -> bool: return p.fix_label == "Make map asset"),
		"no loose model is left")
	(found.filter(func(p: Dictionary) -> bool: return p.node == empty)[0].fix as Callable) \
		.call().apply(road_map)
	expect(not is_instance_valid(empty), "the empty mesh's fix deletes it")
	road_map.free()


func _test_in_the_way() -> void:
	var road_map := RoadMap.new()
	var lane := TrafficLane.new()
	lane.name = "Lane"
	lane.curve = MapKitTools.straight_from(40.0)
	road_map.add_child(lane)
	var entry := catalogue_entry("cone")
	var on_lane := AssetCatalogue.make(entry)
	on_lane.name = "OnLane"
	on_lane.position = Vector3(0.6, 0, -20)
	var past_end := AssetCatalogue.make(entry)
	past_end.name = "PastEnd"
	past_end.position = Vector3(0, 0, -41.5)
	var beside := AssetCatalogue.make(entry)
	beside.name = "Beside"
	beside.position = Vector3(2.5, 0, -10)
	var looks := AssetCatalogue.make(entry)
	looks.name = "Looks"
	looks.position = Vector3(0, 0, -30)
	looks.body_type = null
	for asset in [on_lane, past_end, beside, looks]:
		road_map.add_child(asset)
	root.add_child(road_map)
	var in_way := MapProblems.problems(road_map).filter(func(p: Dictionary) -> bool:
		return p.message.contains("in the way"))
	var named := in_way.map(func(p: Dictionary) -> String: return p.node.name)
	expect(named == ["OnLane", "PastEnd"] and in_way.all(func(p: Dictionary) -> bool:
			return p.message.contains("Lane") and p.fix_label == "Make look only"),
		"a solid model on a lane or just past its end is in road users' way, one beside it or "
		+ "looks only is not: %s" % [named])
	if not in_way.is_empty():
		(in_way[0].fix as Callable).call().apply(road_map)
	on_lane.rebuild()
	expect(on_lane.body_type == null and on_lane.bodies().is_empty(),
		"the fix makes it looks only, so road users pass")
	road_map.free()


func _test_problems() -> void:
	var road_map := RoadMap.new()
	var check := ContactCheck.new()
	road_map.add_child(check)
	var found := MapProblems.problems(road_map)
	var messages := found.map(func(p: Dictionary) -> String: return p.message)
	expect(messages.any(func(m: String) -> bool: return m.contains("MapSpawn"))
		and messages.any(func(m: String) -> bool: return m.contains("checks belong to a scenario")),
		"a map without a spawn and with a check has both flagged")
	road_map.free()
	var other := Node3D.new()
	expect(MapProblems.problems(other).size() == 1, "a scene that is not a map is flagged")
	other.free()


const USERS := "user://map_kit_test_users/"


func _test_map_files() -> void:
	_remove(ROOT)
	_remove(USERS)
	DirAccess.make_dir_recursive_absolute(USERS)
	MapFiles.create_map("high_street", "High Street", ROOT)
	var user := USERS + "uses_it.tscn"
	var file := FileAccess.open(user, FileAccess.WRITE)
	file.store_string("[ext_resource type=\"PackedScene\" path=\"%s\" id=\"map\"]\n"
		% MapFiles.map_path("high_street", ROOT))
	file.close()
	var users := MapFiles.map_users(MapFiles.map_path("high_street", ROOT), USERS)
	expect(users == PackedStringArray([user]),
		"a scenario instancing a map is one of its users")

	expect(MapFiles.rename_map("high_street", "Bad Name", ROOT, USERS) != ""
		and MapFiles.rename_map("no_such", "fine", ROOT, USERS) != "",
		"renaming refuses a bad name and a missing map")
	expect(MapFiles.rename_map("high_street", "market_street", ROOT, USERS) == "",
		"a map renames")
	var entry := MapCatalogue.scan(ROOT)
	expect(entry.size() == 1 and entry[0].id == &"market_street" and entry[0].title == "High Street"
		and FileAccess.get_file_as_string(user).contains(
			MapFiles.map_path("market_street", ROOT)),
		"renaming moves the folder, sets the id, keeps the title, and repoints its users")

	var saved := load(MapFiles.map_path("market_street", ROOT)) as PackedScene
	saved.resource_path = ""
	ResourceSaver.save(saved, MapFiles.map_path("market_street", ROOT))
	expect(MapFiles.duplicate_map("market_street", "market_copy", "Market copy", ROOT) == "",
		"a map duplicates")
	var copy_text := FileAccess.get_file_as_string(MapFiles.map_path("market_copy", ROOT))
	var names := MapCatalogue.scan(ROOT).map(func(e: MapCatalogue.Entry) -> String: return e.title)
	expect(not copy_text.contains("uid=\"uid://") and names == ["Market copy", "High Street"],
		"a duplicate has its own title and no shared uid")
	expect(MapFiles.duplicate_map("market_street", "market_copy", "", ROOT) != "",
		"duplicating onto an existing map is refused")

	expect(MapFiles.delete_map("market_street", ROOT, USERS, false) != ""
		and FileAccess.file_exists(MapFiles.map_path("market_street", ROOT)),
		"a map a scenario uses is not deleted")
	expect(MapFiles.delete_map("market_copy", ROOT, USERS, false) == ""
		and not DirAccess.dir_exists_absolute(ROOT + "market_copy"),
		"a map no scenario uses is deleted with its folder")
	_remove(ROOT)
	_remove(USERS)


## A map with [param nodes] under it, in the tree.
func _map(nodes: Array) -> RoadMap:
	var road_map := RoadMap.new()
	for node: Node in nodes:
		road_map.add_child(node)
		MapKitTools.own(node, road_map)
	root.add_child(road_map)
	return road_map


func _segment(from: Vector3, to: Vector3) -> RoadSegment:
	var segment := RoadSegment.new()
	segment.curve = Curve3D.new()
	segment.curve.add_point(from)
	segment.curve.add_point(to)
	return segment


func _test_road_ends() -> void:
	var road := _segment(Vector3(0, 0, 0), Vector3(0, 0, -20))
	var road_map := _map([road])
	var ends := RoadNetwork.road_ends(road_map)
	expect(ends.size() == 2 and ends[0].transform.origin.is_equal_approx(Vector3.ZERO)
		and (-ends[0].transform.basis.z).is_equal_approx(Vector3.BACK)
		and ends[1].transform.origin.is_equal_approx(Vector3(0, 0, -20))
		and (-ends[1].transform.basis.z).is_equal_approx(Vector3.FORWARD)
		and is_equal_approx(ends[0].width, 7.0),
		"a road has two open ends, each facing out of it")
	var junction := RoadJunction.new()
	junction.position = Vector3(0, 0, -27.5)
	road_map.add_child(junction)
	ends = RoadNetwork.road_ends(road_map)
	expect(ends.size() == 4 and not ends.any(func(e: Dictionary) -> bool:
			return e.transform.origin.is_equal_approx(Vector3(0, 0, -20))),
		"where a junction's arm meets the road, neither end is open")
	road_map.free()


func _test_extend() -> void:
	var road := _segment(Vector3(0, 0, 0), Vector3(0, 0, -20))
	road.lanes_each_way = 2
	var road_map := _map([road])
	var edit := RoadNetwork.extend_road(road_map, road, Vector3(0, 0, -25))
	var added := edit.added()
	var next := added[0] as RoadSegment if added.size() == 1 else null
	expect(next != null and next.lanes_each_way == 2
		and next.position.is_equal_approx(Vector3(0, 0, -20))
		and (-next.transform.basis.z).is_equal_approx(Vector3.FORWARD),
		"extending starts a road like it at its far end, heading on")
	edit.apply(road_map)
	expect(RoadNetwork.road_ends(road_map).size() == 2, "the extended road joins the old one")

	var junction_edit := RoadNetwork.junction_at_end(road_map, road, RoadJunction.Shape.T,
		Vector3(0, 0, 5))
	var junction: RoadJunction = null
	if not junction_edit.is_empty():
		junction = junction_edit.added()[0] as RoadJunction
	expect(junction != null and is_equal_approx(junction.road_width, 14.0),
		"a junction at a road's end takes the road's width")
	junction_edit.apply(road_map)
	var open := RoadNetwork.road_ends(road_map)
	expect(open.size() == 3 and not open.any(func(e: Dictionary) -> bool: return e.node == road),
		"the junction's south arm joins the road's end")
	expect(RoadNetwork.extend_road(road_map, road).is_empty(),
		"a road with no open end is not extended")
	road_map.free()


func _test_generate_all() -> void:
	var road_map: RoadMap = load("res://maps/sample_town/sample_town.tscn").instantiate()
	root.add_child(road_map)
	RoadNetwork.generate_all(road_map).apply(road_map)
	var lanes := road_map.nodes().filter(func(n: Node) -> bool: return n is TrafficLane)
	var open := RoadNetwork.road_ends(road_map)
	var dead := lanes.filter(func(l: TrafficLane) -> bool:
		return l.next.is_empty() and not _leaves(road_map, l, open))
	expect(lanes.size() > 8 and dead.is_empty(),
		"generating the whole map links every lane that does not leave it %s"
			% [dead.map(func(l: Node) -> String: return l.get_path())])
	expect(MapProblems.problems(road_map).all(func(p: Dictionary) -> bool:
			return p.fix == null or not p.message.contains("not linked")),
		"after generating, no lane is left unlinked")
	expect(RoadNetwork.link_lanes(road_map).is_empty(), "linking again changes nothing")
	road_map.free()


## Whether [param lane] ends at one of the [param open] road ends, leaving the map.
static func _leaves(road_map: RoadMap, lane: TrafficLane, open: Array[Dictionary]) -> bool:
	var end := RoadMap.to_map(lane, road_map) * lane.curve.sample_baked(lane.length())
	for road_end in open:
		if road_end.transform.origin.distance_to(end) < road_end.width:
			return true
	return false


func _test_fixes() -> void:
	var zone := TriggerZone.new()
	var road := _segment(Vector3(0, 0, 0), Vector3(0, 0, -20))
	var road_map := _map([zone, road])
	var found := MapProblems.problems(road_map)
	var labels := found.filter(func(p: Dictionary) -> bool: return p.fix != null) \
		.map(func(p: Dictionary) -> String: return p.fix_label)
	expect(labels.has("Add spawn") and labels.has("Add box") and labels.has("Generate"),
		"a missing spawn, a zone without a box, and a bare road have fixes %s" % [labels])
	for problem in found:
		if problem.fix != null:
			(problem.fix as Callable).call().apply(road_map)
	var left := MapProblems.problems(road_map).filter(func(p: Dictionary) -> bool:
		return p.severity == MapProblems.WARNING)
	expect(left.is_empty(), "fixing each problem leaves no warning %s"
		% [left.map(func(p: Dictionary) -> String: return p.message)])
	var spawn := road_map.spawns()[0] if not road_map.spawns().is_empty() else null
	expect(spawn != null and RoadNetwork.on_road(road_map, spawn.position),
		"the added spawn is on the road")
	road_map.free()


func _test_joining() -> void:
	var road := _segment(Vector3(0, 0, 0), Vector3(0, 0, -20))
	var road_map := _map([road])
	var placed := RoadSegment.new()
	var where: Variant = RoadNetwork.joining_transform(road_map, placed, Vector3(1, 0, -22))
	expect(where != null and (where as Transform3D).origin.is_equal_approx(Vector3(0, 0, -20))
		and placed.curve.get_point_position(0).is_equal_approx(Vector3.ZERO),
		"a road placed near an open end starts on it")
	var junction := RoadJunction.new()
	where = RoadNetwork.joining_transform(road_map, junction, Vector3(0, 0, 2))
	var arm: Variant = null
	if where != null:
		arm = (where as Transform3D) * junction.arm_end(RoadJunction.Arm.SOUTH).origin
	expect(arm != null and (arm as Vector3).is_equal_approx(Vector3.ZERO),
		"a junction placed near an open end joins it by its south arm")
	expect(RoadNetwork.joining_transform(road_map, RoadSegment.new(), Vector3(20, 0, 20)) == null,
		"a piece far from every end is not joined")
	placed.free()
	junction.free()
	road_map.free()


func _test_overlay_marks() -> void:
	var road := _segment(Vector3(0, 0, 0), Vector3(0, 0, -40))
	var spawn := MapSpawn.new()
	spawn.name = "Spawn"
	spawn.position = Vector3(1.75, 0, -2)
	var road_map := _map([road, spawn])
	road.generate_lanes()
	var marks := MapKitOverlay.marks(road_map)
	expect(marks.arrows.size() == 8 and marks.ends.size() == 2 and marks.open.size() == 2
		and marks.labels.size() == 1 and marks.labels[0][1] == "1 Spawn"
		and marks.ends.all(func(e: Array) -> bool: return not e[1]),
		"the overlay marks a road's lane arrows, its unlinked lane ends, its open ends, and spawns")
	road_map.free()


static func _remove(file_path: String) -> void:
	if not DirAccess.dir_exists_absolute(file_path):
		return
	for folder in DirAccess.get_directories_at(file_path):
		_remove(file_path.path_join(folder))
	for file in DirAccess.get_files_at(file_path):
		DirAccess.remove_absolute(file_path.path_join(file))
	DirAccess.remove_absolute(file_path)
