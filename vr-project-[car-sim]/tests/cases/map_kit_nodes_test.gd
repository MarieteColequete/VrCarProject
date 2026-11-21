extends TestCase
## The map authoring nodes: a road segment's lanes and markings, a junction's lines, signs, and
## props, and a map built from them baking and driving.


func run() -> void:
	_test_segment_lanes()
	_test_segment_markings()
	_test_junction()
	_test_road_look()
	_test_sign()
	await _test_bake()


func _segment(lanes_each_way := 1, one_way := false) -> RoadSegment:
	var segment := RoadSegment.new()
	segment.curve = Curve3D.new()
	segment.curve.add_point(Vector3(0, 0, 0))
	segment.curve.add_point(Vector3(0, 0, -40))
	segment.lanes_each_way = lanes_each_way
	segment.one_way = one_way
	segment.speed_limit_kmh = 36.0
	return segment


func _test_segment_lanes() -> void:
	var segment := _segment()
	root.add_child(segment)
	var lanes := segment.generate_lanes()
	var ahead := lanes[0] if lanes.size() > 0 else null
	var back := lanes[1] if lanes.size() > 1 else null
	expect(lanes.size() == 2 and ahead.point_at(0.0).is_equal_approx(Vector3(1.75, 0, 0))
		and ahead.point_at(ahead.length()).is_equal_approx(Vector3(1.75, 0, -40))
		and back.point_at(0.0).is_equal_approx(Vector3(-1.75, 0, -40)),
		"a two-way road gets a lane each way, on the right of its direction of travel")
	expect(is_equal_approx(ahead.speed_limit, 10.0), "generated lanes take the segment's limit")
	segment.lanes_each_way = 2
	lanes = segment.generate_lanes()
	expect(lanes.size() == 4 and segment.get_child_count() == 4
		and lanes[0].right == lanes[1] and lanes[1].left == lanes[0] and lanes[0].left == null
		and lanes[2].right == lanes[3],
		"generating again replaces the lanes, and lanes running the same way are neighbours")
	segment.free()

	var one_way := _segment(2, true)
	root.add_child(one_way)
	lanes = one_way.generate_lanes()
	expect(lanes.size() == 2 and lanes[0].point_at(0.0).is_equal_approx(Vector3(-1.75, 0, 0))
		and lanes[1].point_at(0.0).is_equal_approx(Vector3(1.75, 0, 0)),
		"a one-way road's lanes all run with the curve, across its width")
	one_way.free()


func _test_segment_markings() -> void:
	var segment := _segment(2)
	root.add_child(segment)
	var markings := segment.generate_markings()
	var kinds := markings.map(func(m: RoadMarking) -> int: return m.kind)
	expect(markings.size() == 5 and kinds.count(RoadMarking.Kind.KERB) == 2
		and kinds.count(RoadMarking.Kind.DASHED) == 3
		and markings[0].world_points()[0].is_equal_approx(Vector3(7, 0, 0)),
		"markings: kerbs at the edges, a dashed centre line, and lines between lanes")
	segment.centre = RoadSegment.Centre.SOLID
	markings = segment.generate_markings()
	expect(markings.size() == 5 and segment.get_child_count() == 5
		and markings.any(func(m: RoadMarking) -> bool: return m.kind == RoadMarking.Kind.SOLID),
		"generating again replaces the markings with the chosen centre line")
	segment.free()


## The mesh a road node draws, its internal child.
static func _drawn(node: Node) -> Mesh:
	for child in node.get_children(true):
		if child is MeshInstance3D:
			return (child as MeshInstance3D).mesh
	return null


func _test_road_look() -> void:
	expect(RoadKit.available(), "the road kit's tiles load")
	var segment := _segment(2)
	root.add_child(segment)
	segment.rebuild()
	var box := _drawn(segment).get_aabb() if _drawn(segment) else AABB()
	expect(segment.kit_look() and is_equal_approx(box.size.x, 14.0 + 2.0 * RoadKit.PAVEMENT)
		and is_equal_approx(box.size.z, 40.0)
		and is_equal_approx(box.end.y, RoadMarking.KERB_HEIGHT),
		"a road is drawn in the kit's look: its lanes' width, a pavement each side, kerb high")
	var kerbs := segment.generate_markings().filter(func(m: RoadMarking) -> bool:
		return m.kind == RoadMarking.Kind.KERB)
	expect(kerbs.size() == 2 and kerbs.all(func(m: RoadMarking) -> bool: return not m.paint),
		"its kerb lines are judged but not drawn over the kit's kerbs")
	segment.kerbs = false
	segment.rebuild()
	box = _drawn(segment).get_aabb()
	expect(is_equal_approx(box.size.x, 14.0) and box.end.y < 0.05,
		"without kerbs, the asphalt alone")
	segment.surface = RoadSegment.ASPHALT
	segment.rebuild()
	expect(not segment.kit_look() and _drawn(segment).surface_get_material(0) == RoadSegment.ASPHALT,
		"a plain surface set draws the flat road instead")
	segment.free()

	var junction := RoadJunction.new()
	junction.shape = RoadJunction.Shape.T
	root.add_child(junction)
	box = _drawn(junction).get_aabb()
	var reach := junction.road_width / 2.0 + junction.arm_length
	expect(is_equal_approx(box.position.x, -reach) and is_equal_approx(box.end.x, reach)
		and is_equal_approx(box.end.z, reach)
		and is_equal_approx(box.position.z, -junction.road_width / 2.0 - RoadKit.PAVEMENT),
		"a T pad reaches its three arms' ends, a pavement along its closed side")
	junction.free()


func _test_junction() -> void:
	var junction := RoadJunction.new()
	junction.shape = RoadJunction.Shape.T
	junction.controlled_arms = 1 << RoadJunction.Arm.SOUTH
	junction.line = RoadJunction.Line.STOP
	root.add_child(junction)
	var lines := junction.generate_lines()
	expect(junction.arms().size() == 3 and not junction.arms().has(RoadJunction.Arm.NORTH),
		"a T junction has no north arm")
	expect(lines.size() == 1 and lines[0].kind == RoadMarking.Kind.STOP_LINE
		and lines[0].world_points()[0].z > 3.5 and lines[0].world_points()[-1].x > 3.0,
		"a controlled arm gets its line across the incoming half")
	var turns := junction.make_lanes()
	expect(turns.size() == 6
		and turns.all(func(l: TrafficLane) -> bool: return l.get_parent() == null),
		"a T junction's lanes join each of its three arms to the two others, unattached")
	junction.shape = RoadJunction.Shape.CROSSROADS
	var through := junction.generate_lanes()
	var south_north := through.filter(func(l: TrafficLane) -> bool: return l.name == "SouthToNorth")
	var south_east := through.filter(func(l: TrafficLane) -> bool: return l.name == "SouthToEast")
	expect(through.size() == 12 and south_north.size() == 1 and south_east.size() == 1
		and south_north[0].point_at(0.0).is_equal_approx(Vector3(1.75, 0, 7.5))
		and south_north[0].point_at(south_north[0].length()).is_equal_approx(Vector3(1.75, 0, -7.5))
		and south_east[0].point_at(south_east[0].length()).is_equal_approx(Vector3(7.5, 0, 1.75)),
		"a crossroads' lanes run on the right, in from one arm and out by each other")
	junction.generate_lanes()
	expect(junction.generated(RoadJunction.LANES).size() == 12
		and junction.generated(RoadJunction.LINES).size() == 1,
		"generating lanes again replaces them and leaves the lines")
	var end := junction.arm_end(RoadJunction.Arm.EAST)
	expect(end.origin.is_equal_approx(Vector3(7.5, 0, 0))
		and (-end.basis.z).is_equal_approx(Vector3.RIGHT),
		"an arm's end is where a road leaving by it starts, facing out")
	junction.free()


func _test_sign() -> void:
	var problems := PackedStringArray()
	for kind in RoadSign.Kind.values():
		var road_sign := RoadSign.new()
		road_sign.kind = kind
		root.add_child(road_sign)
		if road_sign.get_child_count(true) == 0:
			problems.append(RoadSign.Kind.keys()[kind])
		road_sign.free()
	expect(problems.is_empty(), "every sign kind builds %s" % [problems])


func _test_bake() -> void:
	var road_map := RoadMap.new()
	road_map.name = "Kit"
	var spawn := MapSpawn.new()
	spawn.position = Vector3(1.75, 0, 0)
	var segment := _segment()
	var prop := Prop.new()
	prop.preset = Prop.Preset.VAN
	prop.position = Vector3(1.75, 0, -25)
	for node: Node in [spawn, segment, prop]:
		road_map.add_child(node)
		node.owner = road_map
	root.add_child(road_map)
	segment.generate_lanes()
	segment.generate_markings()
	root.remove_child(road_map)
	var packed := PackedScene.new()
	expect(packed.pack(road_map) == OK, "a map built from the kit packs into a scene")
	road_map.free()

	var runner: ExamRunner = RUNNER.instantiate()
	runner.print_results = false
	runner.scenario_scene = null
	root.add_child(runner)
	runner.load_map(packed)
	await process_frame
	var world := runner.world()
	expect(world.store(Schema.MARKING).size() == 3, "the generated markings bake into the world")
	expect(world.store(Schema.OBSTACLE).size() == 1, "a prop bakes into an obstacle")
	var lanes: Dictionary = world.resources[Schema.LANES]
	expect(lanes.size() == 2, "the generated lanes bake into the road network")
	await frames(30)
	expect(runner.session.is_running(), "the kit map drives freely")
	runner.queue_free()
	await process_frame
