extends TestCase
## Other road users: scripted road users, traffic lights, the spawner, and contact.

const TRAFFIC_FIXTURE := preload("res://tests/fixtures/traffic_fixture.tscn")


func run() -> void:
	_test_scripted_agent()
	_test_traffic_light()
	_test_spawner()
	await _test_traffic_drives()


func _test_scripted_agent() -> void:
	var s := sim()
	var line := path(s, Vector3.ZERO, Vector3(0, 0, -20))
	var events := []
	record_sim(s, events)
	var agent := road_user(s, line, {speed = 5.0, start_delay = 1.0})
	tick(s, 30)
	var a := state_of(s, agent)
	expect(a.state == AgentTable.State.WAITING and a.position.is_zero_approx(),
		"a road user waits out its start delay at the start of its path")
	var due: float = time_to(s, agent, 20.0)
	expect(absf(due - (0.5 + 4.0)) < 0.05,
		"time_to counts the remaining delay and the distance at speed (%.3f)" % due)
	tick(s, 90)
	a = state_of(s, agent)
	expect(a.state == AgentTable.State.MOVING and absf(a.progress - 5.0) < 0.25,
		"one second after starting, it is 5 m along at 5 m/s (%.2f)" % a.progress)
	expect(a.facing.is_equal_approx(Vector3(0, 0, -1)), "it faces along its path")
	tick(s, 240)
	a = state_of(s, agent)
	expect(a.state == AgentTable.State.DONE and a.position.is_equal_approx(Vector3(0, 0, -20))
		and events.any(func(e: WorldEvent) -> bool: return e.kind == &"agent_finished"),
		"at the end of its path it stops and reports finished")
	end_sim(s)

	s = sim()
	line = path(s, Vector3.ZERO, Vector3(0, 0, -20))
	var pauser := road_user(s, line, {speed = 5.0, pause_at = 10.0, pause_time = 2.0})
	expect(is_equal_approx(time_to(s, pauser, 20.0), 4.0 + 2.0),
		"time_to includes a pause still ahead")
	tick(s, 180)
	a = state_of(s, pauser)
	expect(a.state == AgentTable.State.PAUSED and is_equal_approx(a.progress, 10.0),
		"it pauses at its pause point")
	tick(s, 70)
	expect(state_of(s, pauser).state == AgentTable.State.MOVING, "and moves on after the pause")
	end_sim(s)

	s = sim()
	line = path(s, Vector3.ZERO, Vector3(0, 0, -20))
	var looper := road_user(s, line, {speed = 10.0, loop = true})
	tick(s, 150)
	a = state_of(s, looper)
	expect(a.state == AgentTable.State.MOVING and absf(a.progress - 5.0) < 0.5,
		"a looping road user starts its next lap (%.2f)" % a.progress)
	end_sim(s)


## The phases a light runs through over [param ticks], triggered at tick [param trigger_at].
func _phases(light: Dictionary, ticks: int, trigger_at := -1) -> Array:
	var seen := []
	var state := light.duplicate()
	state.merge(LightLogic.initial(light), true)
	for i in ticks:
		var next := LightLogic.step(state, DT, i == trigger_at)
		if next.state != state.state:
			seen.append(next.state)
		state.merge(next, true)
	return [seen, state.state]


func _test_traffic_light() -> void:
	var cycle := {mode = TrafficLight.Mode.CYCLE, initial = TrafficLight.Light.RED, red_time = 1.0,
		red_amber_time = 0.5, green_time = 1.0, amber_time = 0.5, trigger_delay = 0.0}
	var phases := _phases(cycle, 190)
	expect(phases[0] == [TrafficLight.Light.RED_AMBER, TrafficLight.Light.GREEN,
		TrafficLight.Light.AMBER, TrafficLight.Light.RED],
		"a cycling light runs red and amber, green, amber, red on its timers: %s" % [phases[0]])
	var approach := {mode = TrafficLight.Mode.ON_APPROACH, initial = TrafficLight.Light.GREEN,
		red_time = 1.0, red_amber_time = 0.5, green_time = 6.0, amber_time = 1.0,
		trigger_delay = 0.5}
	phases = _phases(approach, 120)
	expect(phases[0].is_empty() and phases[1] == TrafficLight.Light.GREEN,
		"a light on approach holds green until triggered")
	phases = _phases(approach, 140, 120)
	expect(phases[1] == TrafficLight.Light.GREEN, "and waits out its trigger delay")
	phases = _phases(approach, 160, 120)
	expect(phases[1] == TrafficLight.Light.AMBER, "then turns amber")
	phases = _phases(approach, 760, 120)
	expect(phases[0] == [TrafficLight.Light.AMBER, TrafficLight.Light.RED,
		TrafficLight.Light.RED_AMBER, TrafficLight.Light.GREEN],
		"and runs once round to green, where it holds: %s" % [phases[0]])


func _filled(seed_value: int, occupancy: float, reserved_index := -1) -> Array[int]:
	var spawner := AgentSpawner.new()
	spawner.random_seed = seed_value
	spawner.occupancy = occupancy
	var eligible: Array[bool] = []
	for i in 6:
		spawner.bays.append(null)
		eligible.append(i != reserved_index)
	var chosen := spawner.choose(eligible)
	spawner.free()
	chosen.sort()
	return chosen


func _test_spawner() -> void:
	var first := _filled(7, 0.5)
	expect(first.size() == 3, "half of six bays are filled (%s)" % [first])
	expect(_filled(7, 0.5) == first, "the same seed fills the same bays")
	var distinct := {}
	for seed_value in [1, 2, 3, 4, 5, 7]:
		distinct[str(_filled(seed_value, 0.5))] = true
	expect(distinct.size() > 1, "different seeds fill different bays")
	expect(_filled(3, 1.0).size() == 5, "a full car park still keeps one bay free")
	expect(not _filled(3, 1.0, 2).has(2), "a reserved bay is never filled")

	# A car park of six bays and a spawner, baked on its own.
	var scenario := Scenario.new()
	var spawner := AgentSpawner.new()
	spawner.random_seed = 7
	for i in 6:
		var bay := ParkingBay.new()
		bay.position = Vector3(i * 3.0, 0, -50)
		scenario.add_child(bay)
		spawner.bays.append(bay)
	scenario.add_child(spawner)
	var car := Node3D.new()
	var probe := VehicleProbe.new()
	car.add_child(probe)
	root.add_child(scenario)
	root.add_child(car)
	var world := World.new()
	Bake.scene(world, scenario, probe)
	var bays := world.store(Schema.BAY)
	var obstacles := world.store(Schema.OBSTACLE)
	var parked := 0
	var standing := 0
	for id in bays.sorted_ids():
		if not bays.get_value(id, &"occupied"):
			continue
		parked += 1
		for row in obstacles.size():
			var centre: Vector3 = (obstacles.column(&"transform")[row] as Transform3D).origin
			if Geo.overhang(bays.get_value(id, &"transform"), bays.get_value(id, &"size"),
					PackedVector3Array([centre])) <= 0.0:
				standing += 1
				break
	expect(parked == 3 and standing == parked,
		"each bay the spawner takes is marked occupied and has a parked car standing in it (%d)"
		% parked)
	scenario.free()
	car.free()


func _test_traffic_drives() -> void:
	var r := await drive([{to = at(-62), speed = 8.0}], TRAFFIC_FIXTURE)
	expect_clean(r, "passing before the pedestrian reaches the lane is clean")

	r = await drive([{to = at(-20), speed = 4.0}, {wait = 8.0}], TRAFFIC_FIXTURE)
	expect(r.has_fault(&"contact_pedestrian") and r.reason == &"eliminated",
		"waiting on the pedestrian's path gets the car walked into: " + r.summary())
