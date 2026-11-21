extends TestCase
## Maps: the folder scan, every map in res://maps/ loading and driving freely, and a restart in
## free drive.

const SCAN_FIXTURES := "res://tests/fixtures/maps/"


func run() -> void:
	_test_scan()
	_test_maps()
	_test_scan_skips()
	await _test_free_drive()
	await _test_restart_keeps_map()


func _test_scan() -> void:
	var maps := MapCatalogue.scan()
	var folders := Array(ResourceLoader.list_directory(MapCatalogue.ROOT)).filter(
		func(name: String) -> bool: return name.ends_with("/"))
	expect(not maps.is_empty() and maps.size() == folders.size(),
		"the scan finds a map for every folder in res://maps/")
	var names := maps.map(func(e: MapCatalogue.Entry) -> String: return e.path)
	var sorted := names.duplicate()
	sorted.sort()
	expect(names == sorted, "the scan lists maps by folder name")
	var entry := MapCatalogue.find(&"stop_junction")
	expect(entry != null and entry.title == "Stop junction"
		and entry.path == "res://maps/stop_junction/stop_junction.tscn",
		"the scan reads a map's id and title without instancing it")


func _test_maps() -> void:
	var problems := PackedStringArray()
	for entry in MapCatalogue.scan():
		var road_map := entry.load_scene().instantiate() as RoadMap
		if road_map == null:
			problems.append("%s's root is not a RoadMap" % entry.path)
			continue
		if road_map.spawns().is_empty():
			problems.append("%s has no MapSpawn" % entry.id)
		for node in road_map.nodes():
			if node is Check:
				problems.append("%s holds the check %s" % [entry.id, node.name])
		road_map.free()
	expect(problems.is_empty(), "every map is a RoadMap with a spawn and no checks %s" % [problems])


func _test_scan_skips() -> void:
	var maps := MapCatalogue.scan(SCAN_FIXTURES)
	expect(maps.size() == 1 and maps[0].id == &"tiny" and maps[0].title == "Tiny",
		"a folder without its matching scene is left out, and a map without a title gets its folder's name")


func _test_free_drive() -> void:
	for entry in MapCatalogue.scan():
		var runner: ExamRunner = RUNNER.instantiate()
		runner.print_results = false
		runner.scenario_scene = null
		root.add_child(runner)
		runner.load_map(entry.load_scene())
		await process_frame
		var start := runner.scenario.map.spawns()[0]
		expect(runner.session.is_running() and runner.session.definition.id == &"free_drive"
			and runner.car.global_position.is_equal_approx(start.global_position),
			"%s loads for free drive with the car at its first spawn" % entry.id)
		await frames(300)
		expect(runner.session.is_running(), "%s drives freely without the attempt ending" % entry.id)
		runner.queue_free()
		await process_frame


func _test_restart_keeps_map() -> void:
	var runner: ExamRunner = RUNNER.instantiate()
	runner.print_results = false
	runner.scenario_scene = null
	root.add_child(runner)
	runner.load_map(MapCatalogue.find(&"stop_junction").load_scene())
	await process_frame
	runner.session.restart()
	await process_frame
	await process_frame
	expect(runner.scenario != null and runner.scenario.definition.id == &"free_drive"
		and runner.scenario.map.id == &"stop_junction",
		"a restart in free drive reloads the same map")
	runner.queue_free()
	await process_frame
