extends TestCase
## The authoring kit: the scenario catalogue, the base scenes scenarios inherit, the maps they are
## set on, and the shared environment.


func run() -> void:
	_test_catalogue()
	await _test_load_definition()


func _test_catalogue() -> void:
	var catalogue := ScenarioCatalogue.main()
	expect(catalogue != null and catalogue.scenarios.size() == 9, "the catalogue lists the nine scenarios")
	var ids := {}
	var problems := PackedStringArray()
	for definition in catalogue.scenarios:
		if ids.has(definition.id):
			problems.append("%s is listed twice" % definition.id)
		ids[definition.id] = true
		if definition.title.is_empty() or definition.category.is_empty() or definition.briefing.is_empty():
			problems.append("%s lacks a title, category, or briefing" % definition.id)
		var scene := definition.load_scene()
		if scene == null:
			problems.append("%s names no loadable scene" % definition.id)
			continue
		var scenario := scene.instantiate() as Scenario
		if scenario == null:
			problems.append("%s's scene root is not a Scenario" % definition.id)
			continue
		if scenario.definition != definition:
			problems.append("%s's scene points at another definition" % definition.id)
		for part in ["Checks/ContactCheck", "Checks/LineCheck", "Checks/TrafficConflictCheck"]:
			if not scenario.has_node(part):
				problems.append("%s has no %s from the base scene" % [definition.id, part])
		if scenario.map == null or scenario.map != scenario.get_node_or_null("Map") \
				or not scenario.map.scene_file_path.begins_with(MapCatalogue.ROOT) \
				or not scenario.map.has_node("Environment") or scenario.start() == null:
			problems.append("%s is not set on a map of %s with an environment and a spawn"
				% [definition.id, MapCatalogue.ROOT])
		elif MapCatalogue.scan().all(func(e: MapCatalogue.Entry) -> bool:
				return e.path != scenario.map.scene_file_path):
			problems.append("%s's map is not found by the map scan" % definition.id)
		if scenario.definition and scenario.definition.policy == null:
			problems.append("%s has no scoring policy" % definition.id)
		scenario.free()
	expect(problems.is_empty(), "every catalogue entry loads a scenario set on a map %s" % [problems])
	expect(catalogue.find(&"roundabout") != null and catalogue.find(&"no_such") == null,
		"the catalogue finds a scenario by id")
	expect(catalogue.in_category("Parking").size() == 2, "the catalogue groups scenarios by category")


func _test_load_definition() -> void:
	var runner: ExamRunner = RUNNER.instantiate()
	runner.print_results = false
	runner.scenario_scene = null
	root.add_child(runner)
	runner.load_definition(ScenarioCatalogue.main().find(&"bay_parking"))
	await process_frame
	expect(runner.scenario != null and runner.scenario.definition.id == &"bay_parking"
		and runner.session.is_running(), "the runner loads and starts a scenario from its definition")
	var environment := runner.scenario.find_child("Environment", true, false) as RoadEnvironment
	await physics_frame
	var down := PhysicsRayQueryParameters3D.create(Vector3(0, 5, -10), Vector3(0, -5, -10))
	expect(environment != null
		and not runner.scenario.get_world_3d().direct_space_state.intersect_ray(down).is_empty(),
		"the shared environment gives the car ground to drive on")
	runner.queue_free()
	await process_frame
