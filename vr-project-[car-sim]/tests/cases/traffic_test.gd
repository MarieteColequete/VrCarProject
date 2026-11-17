extends TestCase
## Other road users: scripted agents, traffic lights, the spawner, and contact.

const TRAFFIC_FIXTURE := preload("res://tests/fixtures/traffic_fixture.tscn")


func run() -> void:
	await _test_scripted_agent()
	await _test_traffic_light()
	await _test_spawner()
	await _test_traffic_drives()


func _straight_path(from: Vector3, to: Vector3) -> Path3D:
	var path := Path3D.new()
	path.curve = Curve3D.new()
	path.curve.add_point(from)
	path.curve.add_point(to)
	root.add_child(path)
	return path


func _test_scripted_agent() -> void:
	var path := _straight_path(Vector3.ZERO, Vector3(0, 0, -20))
	var agent := ScriptedAgent.new()
	agent.path = path
	agent.speed = 5.0
	agent.start_delay = 1.0
	var finished := [false]
	agent.finished.connect(func() -> void: finished[0] = true)
	root.add_child(agent)
	await frames(30)
	expect(agent.state == ScriptedAgent.State.WAITING and agent.global_position.is_zero_approx(),
		"an agent waits out its start delay at the start of its path")
	expect(absf(agent.time_to(20.0) - (0.5 + 4.0)) < 0.05,
		"time_to counts the remaining delay and the distance at speed (%.3f)" % agent.time_to(20.0))
	await frames(90)
	expect(agent.state == ScriptedAgent.State.MOVING and absf(agent.progress - 5.0) < 0.2,
		"one second after starting, it is 5 m along at 5 m/s (%.2f)" % agent.progress)
	expect((-agent.global_basis.z).is_equal_approx(Vector3(0, 0, -1)), "it faces along its path")
	await frames(240)
	expect(agent.state == ScriptedAgent.State.DONE and finished[0]
		and agent.global_position.is_equal_approx(Vector3(0, 0, -20)),
		"at the end of its path it stops and reports finished")
	agent.free()

	var pauser := ScriptedAgent.new()
	pauser.path = path
	pauser.speed = 5.0
	pauser.pause_at = 10.0
	pauser.pause_time = 2.0
	root.add_child(pauser)
	expect(is_equal_approx(pauser.time_to(20.0), 4.0 + 2.0), "time_to includes a pause still ahead")
	await frames(180)
	expect(pauser.state == ScriptedAgent.State.PAUSED and is_equal_approx(pauser.progress, 10.0),
		"it pauses at its pause point")
	await frames(70)
	expect(pauser.state == ScriptedAgent.State.MOVING, "and moves on after the pause")
	pauser.free()

	var looper := ScriptedAgent.new()
	looper.path = path
	looper.speed = 10.0
	looper.loop = true
	root.add_child(looper)
	await frames(150)
	expect(looper.state == ScriptedAgent.State.MOVING and absf(looper.progress - 5.0) < 0.3,
		"a looping agent starts its next lap (%.2f)" % looper.progress)
	expect(looper.collision_layer == Layers.OBSTACLE
		and not looper.is_in_group(Layers.GROUP_PEDESTRIAN),
		"a car agent is an obstacle")
	looper.free()
	path.free()


func _test_traffic_light() -> void:
	var light := TrafficLight.new()
	light.red_time = 1.0
	light.red_amber_time = 0.5
	light.green_time = 1.0
	light.amber_time = 0.5
	var seen: Array[TrafficLight.Light] = []
	light.state_changed.connect(func(s: TrafficLight.Light) -> void: seen.append(s))
	root.add_child(light)
	expect(light.state == TrafficLight.Light.RED and light.is_red(), "a cycling light starts at its initial phase")
	await frames(190)
	expect(seen == [TrafficLight.Light.RED_AMBER, TrafficLight.Light.GREEN, TrafficLight.Light.AMBER,
		TrafficLight.Light.RED], "it runs red and amber, green, amber, red on its timers: %s" % [seen])
	light.free()

	var approach := TrafficLight.new()
	approach.mode = TrafficLight.Mode.ON_APPROACH
	approach.initial = TrafficLight.Light.GREEN
	approach.trigger_delay = 0.5
	approach.amber_time = 1.0
	approach.red_time = 1.0
	approach.red_amber_time = 0.5
	seen.clear()
	approach.state_changed.connect(func(s: TrafficLight.Light) -> void: seen.append(s))
	root.add_child(approach)
	await frames(120)
	expect(seen.is_empty() and approach.state == TrafficLight.Light.GREEN,
		"a light on approach holds green until triggered")
	approach._on_triggered(null)
	await frames(20)
	expect(approach.state == TrafficLight.Light.GREEN, "and waits out its trigger delay")
	await frames(20)
	expect(approach.state == TrafficLight.Light.AMBER, "then turns amber")
	await frames(600)
	expect(seen == [TrafficLight.Light.AMBER, TrafficLight.Light.RED, TrafficLight.Light.RED_AMBER,
		TrafficLight.Light.GREEN], "and runs once round to green, where it holds: %s" % [seen])
	approach.free()


func _bays(count: int) -> Array[ParkingBay]:
	var bays: Array[ParkingBay] = []
	for i in count:
		var bay := ParkingBay.new()
		bay.position = Vector3(i * 3.0, 0, -50)
		root.add_child(bay)
		bays.append(bay)
	return bays


func _filled_indices(seed_value: int, occupancy: float, reserved_index := -1) -> Array[int]:
	var bays := _bays(6)
	if reserved_index >= 0:
		bays[reserved_index].reserved = true
	var spawner := AgentSpawner.new()
	spawner.random_seed = seed_value
	spawner.occupancy = occupancy
	spawner.bays = bays
	root.add_child(spawner)
	var out: Array[int] = []
	for i in bays.size():
		if bays[i].occupied:
			out.append(i)
	spawner.free()
	for bay in bays:
		bay.free()
	return out


func _test_spawner() -> void:
	var first := _filled_indices(7, 0.5)
	expect(first.size() == 3, "half of six bays are filled (%s)" % [first])
	expect(_filled_indices(7, 0.5) == first, "the same seed fills the same bays")
	var others := [first]
	for seed_value in [1, 2, 3, 4, 5]:
		others.append(_filled_indices(seed_value, 0.5))
	var distinct := {}
	for set_ in others:
		distinct[str(set_)] = true
	expect(distinct.size() > 1, "different seeds fill different bays")
	expect(_filled_indices(3, 1.0).size() == 5, "a full car park still keeps one bay free")
	expect(not _filled_indices(3, 1.0, 2).has(2), "a reserved bay is never filled")

	var bays := _bays(2)
	var spawner := AgentSpawner.new()
	spawner.occupancy = 0.5
	spawner.keep_free = 0
	spawner.bays = bays
	root.add_child(spawner)
	await physics_frame
	await physics_frame
	var taken := bays[0] if bays[0].occupied else bays[1]
	var other := bays[1] if taken == bays[0] else bays[0]
	taken.occupied = false
	expect(not taken.is_free() and other.is_free(),
		"a spawned car stands in its bay, so the bay reads as taken even unmarked")
	spawner.free()
	for bay in bays:
		bay.free()


func _test_traffic_drives() -> void:
	var r := await drive([{to = at(-62), speed = 8.0}], TRAFFIC_FIXTURE)
	expect_clean(r, "passing before the pedestrian reaches the lane is clean")

	r = await drive([{to = at(-20), speed = 4.0}, {wait = 8.0}], TRAFFIC_FIXTURE)
	expect(r.has_fault(&"contact_pedestrian") and r.reason == &"eliminated",
		"waiting on the pedestrian's path gets the car walked into: " + r.summary())
