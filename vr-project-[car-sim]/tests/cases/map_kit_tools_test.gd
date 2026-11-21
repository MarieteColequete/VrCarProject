extends TestCase
## The Map Kit's helpers: creating a map, the palette, linking lanes, solid bodies, snapping, and
## a map's problems.

const ROOT := "user://map_kit_test/"


func run() -> void:
	_test_create_map()
	_test_palette()
	_test_lane_links()
	_test_obstacle_body()
	_test_problems()
	expect(MapKitTools.snapped(Vector3(1.26, 0.3, -0.74)).is_equal_approx(Vector3(1.5, 0.3, -0.5)),
		"snapping keeps the height and rounds to half a metre")


func _test_create_map() -> void:
	_remove(ROOT)
	expect(not MapKitTools.is_map_name("Main Street") and not MapKitTools.is_map_name("1st")
		and MapKitTools.is_map_name("main_street_2"), "map names are lower case folder names")
	var path := MapKitTools.create_map("main_street", "Main Street", ROOT)
	var entries := MapCatalogue.scan(ROOT)
	expect(path == ROOT + "main_street/main_street.tscn" and entries.size() == 1
		and entries[0].id == &"main_street" and entries[0].title == "Main Street",
		"a new map is a folder and scene the scan finds, with its id and title")
	var road_map := load(path).instantiate() as RoadMap if not path.is_empty() else null
	expect(road_map != null and road_map.has_node("Environment") and road_map.spawns().size() == 1
		and (load(path) as PackedScene).get_state().get_node_instance(0) != null,
		"a new map inherits the map base, with its environment and spawn")
	if road_map:
		road_map.free()
	expect(MapKitTools.create_map("main_street", "", ROOT).is_empty(),
		"an existing map is not overwritten")
	_remove(ROOT)


func _test_palette() -> void:
	var road_map: RoadMap = load(MapKitTools.BASE).instantiate()
	root.add_child(road_map)
	var problems := PackedStringArray()
	var labels := {}
	for piece in MapKitTools.pieces():
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
	for problem in MapKitTools.problems(road_map):
		if not problem.node is TrafficLight and not problem.node is TrafficSource:
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
	var links := MapKitTools.lane_links([a, b, back, far])
	expect(links.size() == 1 and links.has(a) and links[a] == [b],
		"a lane links to the lane starting where it ends and heading on, not back or far away")
	a.next = [b]
	expect(MapKitTools.lane_links([a, b, back, far]).is_empty(), "a link already made is not repeated")
	for lane in [a, b, back, far]:
		lane.free()


func _test_obstacle_body() -> void:
	var holder := Node3D.new()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(2, 1, 4)
	mesh.mesh = box
	mesh.position = Vector3(0, 0.5, 1)
	holder.add_child(mesh)
	var body := MapKitTools.obstacle_body(holder)
	var shape := body.get_child(0) as CollisionShape3D if body else null
	expect(body != null and body.collision_layer == Layers.OBSTACLE
		and shape.shape.size.is_equal_approx(Vector3(2, 1, 4))
		and shape.position.is_equal_approx(Vector3(0, 0.5, 1)),
		"a solid body boxes the node's meshes on the obstacle layer")
	expect(MapKitTools.obstacle_body(Node3D.new()) == null, "a node with no mesh gets no body")
	if body:
		body.free()
	holder.free()


func _test_problems() -> void:
	var road_map := RoadMap.new()
	var check := ContactCheck.new()
	road_map.add_child(check)
	var found := MapKitTools.problems(road_map)
	var messages := found.map(func(p: Dictionary) -> String: return p.message)
	expect(messages.any(func(m: String) -> bool: return m.contains("MapSpawn"))
		and messages.any(func(m: String) -> bool: return m.contains("checks belong to a scenario")),
		"a map without a spawn and with a check has both flagged")
	road_map.free()
	var other := Node3D.new()
	expect(MapKitTools.problems(other).size() == 1, "a scene that is not a map is flagged")
	other.free()


static func _remove(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for folder in DirAccess.get_directories_at(path):
		_remove(path.path_join(folder))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
