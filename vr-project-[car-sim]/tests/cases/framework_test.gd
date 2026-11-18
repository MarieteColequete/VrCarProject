extends TestCase
## The framework's building blocks: episodes, default faults, configuration warnings, zone
## membership and contact by geometry, and baking checks into rules.

const CHECKS := "res://scenarios/checks/"
const POLICY := preload("res://scenarios/data/default_policy.tres")


func run() -> void:
	_test_episode()
	_test_default_faults()
	_test_configuration_warnings()
	_test_detection()
	await _test_bake()


func _test_episode() -> void:
	var e := Vector2.ZERO
	var fired: Array[bool] = []
	for i in 4:
		var next := Episode.next(e, true, 0.5, 1.0)
		fired.append(Episode.fired(e, next))
		e = next
	expect(fired == [false, false, true, false],
		"an episode fires once, on the tick it first outlasts its grace: %s" % [fired])
	expect(Episode.next(e, false, 0.5, 1.0) == Vector2.ZERO, "it resets when the condition ends")


func _test_default_faults() -> void:
	var missing := PackedStringArray()
	var found := 0
	for file in DirAccess.get_files_at(CHECKS):
		if not file.ends_with(".gd"):
			continue
		var script: GDScript = load(CHECKS + file)
		var node: Object = script.new()
		if node is Check:
			for property in node.get_property_list():
				if property.class_name == &"FaultDef":
					found += 1
					var fault: FaultDef = node.get(property.name)
					if fault == null or POLICY.get_tier(fault.tier) == null:
						missing.append("%s.%s" % [file.get_basename(), property.name])
		node.free()
	expect(found > 0 and missing.is_empty(),
		"all %d fault exports default to a fault of a policy tier %s" % [found, missing])


func _test_configuration_warnings() -> void:
	var stop := StopCheck.new()
	expect(stop._get_configuration_warnings().size() == 2,
		"a stop check without its zones warns about both")
	var approach := TriggerZone.new()
	var line := TriggerZone.new()
	stop.approach_zone = approach
	stop.line_zone = line
	expect(stop._get_configuration_warnings().is_empty(), "a configured stop check has no warning")
	var junction := JunctionCheck.new()
	junction.judge_on_exit = true
	expect(junction._get_configuration_warnings().size() == 1,
		"a junction check without exits asks for them")
	expect(approach._get_configuration_warnings().size() == 1, "a zone without a box shape warns")
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	approach.add_child(shape)
	expect(approach._get_configuration_warnings().is_empty(), "a zone with a box shape has no warning")
	var agent := ScriptedAgent.new()
	expect(agent._get_configuration_warnings().size() == 1, "an agent without a path warns")
	for node: Node in [stop, approach, line, junction, agent]:
		node.free()


func _test_detection() -> void:
	var world := World.new()
	Schema.define(world)
	var car := world.spawn({vehicle = {transform = Transform3D(Basis(), Vector3(0, 0, 5))}})
	var zone := world.spawn({zone = {transform = Transform3D(Basis(), Vector3(0, 1, 0)),
		half = Vector3(2, 1, 1)}})
	world.spawn({obstacle = {transform = Transform3D(Basis(), Vector3(0, 0.7, -5)),
		size = Vector3(1.8, 1.4, 4.2), name = &"Van"}})
	world.begin_tick(0.1)
	world.apply(Detection.zones(world, 0.1))
	expect(not world.get_value(Schema.ZONE, zone, &"inside") and world.events.is_empty(),
		"a car clear of a zone is not in it")
	world.apply(Delta.new().write(Schema.VEHICLE, car, &"transform",
		Transform3D(Basis(), Vector3(0, 0, 2.5))))
	world.begin_tick(0.1)
	world.apply(Detection.zones(world, 0.1))
	expect(world.get_value(Schema.ZONE, zone, &"entered") and world.events.size() == 1
		and world.events[0].kind == &"zone_entered",
		"a car whose body reaches into a zone, its centre still outside, enters it")
	world.begin_tick(0.1)
	world.apply(Detection.zones(world, 0.1))
	expect(world.get_value(Schema.ZONE, zone, &"inside") and not world.get_value(Schema.ZONE, zone,
		&"entered") and world.events.is_empty(), "and stays in it without entering again")
	world.apply(Delta.new().write(Schema.VEHICLE, car, &"transform",
		Transform3D(Basis(), Vector3(0, 0, -1.5))))
	world.begin_tick(0.1)
	world.apply(Detection.contacts(world, 0.1))
	expect(world.events.size() == 1 and world.events[0].kind == &"contact"
		and not world.events[0].data.pedestrian, "the contact hull touching a parked van is contact")
	world.begin_tick(0.1)
	world.apply(Detection.contacts(world, 0.1))
	expect(world.events.is_empty(), "touching it still is not a new contact")


func _test_bake() -> void:
	var runner := spawn_runner()
	await process_frame
	var world := runner.world()
	var rules := world.store(Schema.RULE)
	var checks := runner.scenario.get_checks()
	var in_order := rules.size() == checks.size()
	for row in rules.size():
		var order: int = rules.column(&"order")[row]
		in_order = in_order and rules.column(&"name")[row] == checks[order].name
	expect(in_order and rules.size() > 0,
		"every check of the scene becomes a rule entity, in tree order (%d)" % rules.size())
	var complete := true
	for check in checks:
		var script := check.rule_script()
		for method in [&"initial", &"step", &"finish"]:
			complete = complete and script.get_script_method_list().any(
				func(m: Dictionary) -> bool: return m.name == method)
	expect(complete, "every rule script has its initial, step, and finish functions")
	runner.queue_free()
	await process_frame
	runner = spawn_runner(load("res://scenarios/scenes/traffic_lights/traffic_lights.tscn"))
	await process_frame
	world = runner.world()
	var index: MarkingIndex = world.resources[Schema.MARKINGS]
	var marking := world.store(Schema.MARKING).ids[0]
	var points: PackedVector3Array = world.get_value(Schema.MARKING, marking, &"points")
	expect(world.store(Schema.MARKING).size() > 0 and index.overlapping(points[0]).has(marking),
		"the scene's markings are baked and indexed (%d)" % world.store(Schema.MARKING).size())
	runner.queue_free()
	await process_frame
