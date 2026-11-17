extends TestCase
## Road users on authored lanes: speed limits, stopping at a red light and going on green,
## queuing, giving way to a vehicle and to traffic on priority lanes, waiting at a crossing in use,
## and taking seeded routes.

var _nodes: Array[Node] = []


func run() -> void:
	await _test_light_and_queue()
	await _test_give_way()
	await _test_crossing()
	await _test_routes()


func _lane(from: Vector3, to: Vector3, limit := 0.0) -> TrafficLane:
	var lane := TrafficLane.new()
	lane.curve = Curve3D.new()
	lane.curve.add_point(from)
	lane.curve.add_point(to)
	lane.speed_limit = limit
	root.add_child(lane)
	_nodes.append(lane)
	return lane


func _agent(lane: Path3D, speed: float, delay := 0.0, seed_value := 0) -> ScriptedAgent:
	var agent := ScriptedAgent.new()
	agent.path = lane
	agent.speed = speed
	agent.start_delay = delay
	agent.route_seed = seed_value
	root.add_child(agent)
	_nodes.append(agent)
	return agent


func _clear() -> void:
	for node in _nodes:
		if is_instance_valid(node):
			node.queue_free()
	_nodes.clear()
	await process_frame


## The front of an agent driving towards -Z.
func _front(agent: ScriptedAgent) -> float:
	return agent.global_position.z - agent.body_size.z * 0.5


func _test_light_and_queue() -> void:
	var light := TrafficLight.new()
	light.red_time = 1000.0
	root.add_child(light)
	_nodes.append(light)
	var lane := _lane(Vector3(0, 0, 100), Vector3(0, 0, -50), 8.0)
	lane.light = light
	lane.stop_offset = 80.0
	var first := _agent(lane, 12.0)
	var second := _agent(lane, 12.0, 2.0)
	await frames(60)
	expect(is_equal_approx(first.current_speed, 8.0), "an agent keeps to its lane's speed limit")
	await frames(900)
	var line_z := 20.0
	expect(first.reaction == &"waiting_light" and is_zero_approx(first.current_speed)
		and _front(first) > line_z and _front(first) < line_z + 2.0,
		"it stops just before the line at a red light (front at z %.2f)" % _front(first))
	var queue_gap := _front(second) - first.global_position.z - first.body_size.z * 0.5
	expect(second.reaction == &"stopped" and queue_gap > 1.0 and queue_gap < 3.5,
		"the next agent queues behind it (%.2f m back)" % queue_gap)
	light._change(TrafficLight.Light.GREEN)
	await frames(600)
	expect(first.global_position.z < line_z - 20.0 and second.global_position.z < line_z,
		"on green both drive on")
	await _clear()


func _test_give_way() -> void:
	# A main lane along -X at z = 0, and a side lane coming up to it from +Z.
	var main := _lane(Vector3(60, 0, -1.75), Vector3(-60, 0, -1.75))
	var side := _lane(Vector3(1.75, 0, 40), Vector3(1.75, 0, 2))
	side.give_way_to = [main]
	var waiting := _agent(side, 8.0)

	var runner := spawn_runner()
	runner.car.input_enabled = false
	await process_frame
	# The player's car stands on the main lane, right at the junction.
	runner.car.global_position = Vector3(3, 0, -1.75)
	runner.car.look_at(runner.car.global_position + Vector3(-1, 0, 0), Vector3.UP)
	await frames(600)
	expect(waiting.reaction == &"yielding" and is_zero_approx(waiting.current_speed),
		"an agent gives way at the line while a vehicle is at the junction")
	runner.car.global_position = Vector3(-40, 0, -30)
	await frames(240)
	expect(waiting.is_done(), "and pulls out once the junction is clear")
	runner.queue_free()
	await _clear()

	main = _lane(Vector3(60, 0, -1.75), Vector3(-60, 0, -1.75))
	side = _lane(Vector3(1.75, 0, 30), Vector3(1.75, 0, 2))
	side.give_way_to = [main]
	# The priority car reaches the junction about 2 s after the side agent reaches its line.
	var priority := _agent(main, 10.0, 0.6)
	waiting = _agent(side, 8.0)
	var priority_x_on_pulling_out := [INF]
	for i in 900:
		await physics_frame
		if is_inf(priority_x_on_pulling_out[0]) and waiting.progress > 1.0 and _front(waiting) < 2.0:
			priority_x_on_pulling_out[0] = priority.global_position.x
	expect(priority_x_on_pulling_out[0] < 1.75 - priority.body_size.z * 0.5,
		"an agent waits for a car on the priority lane to clear the junction (it was at x %.2f)"
		% priority_x_on_pulling_out[0])
	await _clear()


func _test_crossing() -> void:
	var zone := TriggerZone.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(8, 3, 4)
	zone.add_child(shape)
	zone.position = Vector3(0, 1.5, 0)
	var walk := _lane(Vector3(-6, 0, 0), Vector3(6, 0, 0))
	var walker := _agent(walk, 1.0, 1.0)
	walker.pedestrian = true
	walker.body_size = Vector3(0.5, 1.8, 0.5)
	var check := CrossingCheck.new()
	check.crossing_zone = zone
	check.pedestrians = [walker]
	check.add_child(zone)
	root.add_child(check)
	_nodes.append(check)
	var lane := _lane(Vector3(1.75, 0, 40), Vector3(1.75, 0, -40))
	lane.crossings = [check]
	var car := _agent(lane, 8.0)
	var stopped := [false]
	car.reacted.connect(func(kind: StringName, _c: Node3D) -> void:
		if kind == &"yielding":
			stopped[0] = true)
	await frames(600)
	expect(stopped[0] and is_zero_approx(car.current_speed) and _front(car) > 2.0,
		"an agent waits before a crossing in use (front at z %.2f)" % _front(car))
	await frames(900)
	expect(walker.is_done() and car.is_done(), "and goes on once the walker is across")
	await _clear()


func _routes(seed_value: int, wanted: Array[TrafficLane] = []) -> String:
	var stem := _lane(Vector3(0, 0, 20), Vector3(0, 0, 0))
	var left := _lane(Vector3(0, 0, 0), Vector3(-20, 0, -20))
	left.name = "Left"
	var right := _lane(Vector3(0, 0, 0), Vector3(20, 0, -20))
	right.name = "Right"
	stem.next = [left, right]
	var agent := _agent(stem, 10.0, 0.0, seed_value)
	if not wanted.is_empty():
		agent.route = [right if wanted[0] == null else wanted[0]]
	await frames(240)
	var took: String = "Left" if agent.global_position.x < -1.0 else "Right"
	await _clear()
	return took


func _test_routes() -> void:
	var choices := {}
	for seed_value in 8:
		choices[seed_value] = await _routes(seed_value)
	var again := await _routes(3)
	expect(again == choices[3], "the same seed takes the same way (%s)" % again)
	expect(choices.values().has("Left") and choices.values().has("Right"),
		"different seeds take different ways %s" % [choices])
	var null_lane: TrafficLane = null
	expect(await _routes(0, [null_lane]) == "Right", "an agent takes the way its route names")
