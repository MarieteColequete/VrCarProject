extends TestCase
## Road users driving to a checkpoint: the lane router's shortest way, the Map Kit turning a placed
## car into a road user, and that road user driving from where it stands, along the lanes, and
## stopping at the checkpoint.


func run() -> void:
	_test_router()
	_test_make_road_user()
	await _test_drive()


static func _straight(id: int, from: Vector3, to: Vector3, next: Array) -> LaneData:
	var curve := Curve3D.new()
	curve.add_point(from)
	curve.add_point(to)
	return LaneData.of(id, curve, Transform3D(), {is_lane = true,
		next = PackedInt64Array(next)})


func _test_router() -> void:
	# 1 runs north to a fork: 2 carries on north, 3 turns east; 4 is cut off.
	var lanes := {
		1: _straight(1, Vector3(0, 0, 0), Vector3(0, 0, -20), [2, 3]),
		2: _straight(2, Vector3(0, 0, -20), Vector3(0, 0, -60), []),
		3: _straight(3, Vector3(0, 0, -20), Vector3(30, 0, -20), []),
		4: _straight(4, Vector3(50, 0, 0), Vector3(50, 0, -40), []),
	}
	var way := LaneRouter.route(lanes, 1, 5.0, Vector3(20, 0, -21))
	expect(way.reachable and way.on_lane and way.route == PackedInt64Array([3])
		and way.goal_lane == 3 and is_equal_approx(way.goal_at, 20.0),
		"the way to a point turns where it must and stops at the point")
	way = LaneRouter.route(lanes, 1, 5.0, Vector3(0, 0, -15))
	expect(way.route.is_empty() and way.goal_lane == 1 and is_equal_approx(way.goal_at, 15.0),
		"a point ahead on the same lane is reached without turning")
	way = LaneRouter.route(lanes, 1, 5.0, Vector3(50, 0, -20))
	expect(way.reachable and not way.on_lane and way.goal_lane != 4,
		"a point on a lane it cannot reach is not on its way")
	expect(not LaneRouter.route(lanes, 9, 0.0, Vector3.ZERO).reachable,
		"from a lane it does not know, nothing is reachable")


## A map of a 60 metre two-way road with its lanes, a taxi on the right lane, and a checkpoint
## 40 metres ahead.
func _road_map() -> RoadMap:
	var road_map: RoadMap = load(MapKitTools.BASE).instantiate()
	root.add_child(road_map)
	var road := RoadSegment.new()
	road.curve = Curve3D.new()
	road.curve.add_point(Vector3.ZERO)
	road.curve.add_point(Vector3(0, 0, -60))
	road_map.get_node("Roads").add_child(road)
	MapKitTools.own(road, road_map)
	MapKitTools.regenerate(road).apply(road_map)
	var taxi := AssetCatalogue.make(catalogue_entry("taxi"))
	taxi.position = Vector3(1.75, 0, -5)
	road_map.get_node("Props").add_child(taxi)
	var checkpoint := Checkpoint.new()
	checkpoint.name = "Station"
	checkpoint.position = Vector3(1.75, 0, -45)
	road_map.get_node("Traffic").add_child(checkpoint)
	for node: Node in [taxi, checkpoint]:
		MapKitTools.own(node, road_map)
	return road_map


func _test_make_road_user() -> void:
	var road_map := _road_map()
	var taxi := road_map.get_node("Props/Taxi") as MapAsset
	var checkpoint := road_map.get_node("Traffic/Station") as Checkpoint
	var edit := MapKitTools.drive_to(road_map, [taxi, checkpoint], checkpoint)
	var agent := edit.added()[0] as ScriptedAgent if edit.adds.size() == 1 else null
	expect(agent != null and edit.removes == [taxi] and agent.path is TrafficLane
		and agent.path.name == "Lane1" and agent.destination == checkpoint
		and agent.model == taxi.model and agent.body_size.is_equal_approx(taxi.size())
		and agent.position.is_equal_approx(Vector3(1.75, 0, -5)),
		"a placed car becomes a road user on its lane, driving to the checkpoint, looking the same")
	edit.apply(road_map)
	var way := MapKitTools.way_of(road_map, agent)
	expect(way.reachable and way.on_lane and is_equal_approx(way.goal_at, 45.0),
		"the editor finds its way to the checkpoint")
	expect(not MapKitTools.problems(road_map).any(func(p: Dictionary) -> bool:
			return p.node == agent), "a road user that can reach its checkpoint has no problem")
	checkpoint.position = Vector3(-1.75, 0, -45)
	expect(MapKitTools.problems(road_map).any(func(p: Dictionary) -> bool:
			return p.node == agent and p.message.contains("cannot reach")),
		"a checkpoint only on the other way's lane is flagged")
	road_map.free()


func _test_drive() -> void:
	var road_map := _road_map()
	var taxi := road_map.get_node("Props/Taxi") as MapAsset
	var checkpoint := road_map.get_node("Traffic/Station") as Checkpoint
	MapKitTools.drive_to(road_map, [taxi], checkpoint).apply(road_map)
	(road_map.get_node("Spawn") as Node3D).position = Vector3(-1.75, 0, -55)
	root.remove_child(road_map)
	var packed := PackedScene.new()
	expect(packed.pack(road_map) == OK, "the map with a road user packs")
	road_map.free()
	var runner: ExamRunner = RUNNER.instantiate()
	runner.print_results = false
	runner.scenario_scene = null
	root.add_child(runner)
	runner.load_map(packed)
	await process_frame
	var store := runner.world().store(Schema.AGENT)
	var start: Vector3 = store.column(&"position")[0] if store.size() == 1 else Vector3.INF
	expect(start.distance_to(Vector3(1.75, 0, -5)) < 0.5,
		"the road user starts where the car stood, not at the lane's start")
	var models: Array = store.column(&"model")
	expect(store.size() == 1 and String(models[0]).ends_with("taxi.glb")
		and runner._traffic_view.counts().has(models[0]), "it is drawn as the car placed")
	await frames(60 * 12)
	var at: Vector3 = store.column(&"position")[0]
	var state: int = store.column(&"state")[0]
	expect(state == AgentTable.State.DONE and at.distance_to(Vector3(1.75, 0, -45)) < 0.5,
		"it drives to the checkpoint and stops there %s" % [at])
	runner.queue_free()
	await process_frame
