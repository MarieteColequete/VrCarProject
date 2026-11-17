extends TestCase
## Road users that play by the book until forced to react: following and stopping behind what is
## in the way, resuming the script, forced braking when cut in on, pedestrians waiting for a car,
## and reproducible reactions.


func run() -> void:
	await _test_stops_and_resumes()
	await _test_forced_braking()
	await _test_walker_waits()
	await _test_reproducible()


func _path(from: Vector3, to: Vector3) -> Path3D:
	var path := Path3D.new()
	path.curve = Curve3D.new()
	path.curve.add_point(from)
	path.curve.add_point(to)
	root.add_child(path)
	return path


func _agent(path: Path3D, speed: float, pedestrian := false) -> ScriptedAgent:
	var agent := ScriptedAgent.new()
	agent.path = path
	agent.speed = speed
	agent.pedestrian = pedestrian
	if pedestrian:
		agent.body_size = Vector3(0.5, 1.8, 0.5)
		agent.min_gap = 1.0
	root.add_child(agent)
	return agent


## A car held still at the stop junction's spawn point, driving towards -Z at x = 1.75.
func _parked_runner() -> ExamRunner:
	var runner := spawn_runner()
	runner.car.input_enabled = false
	await process_frame
	return runner


func _cleanup(nodes: Array) -> void:
	for node: Node in nodes:
		if is_instance_valid(node):
			node.queue_free()
	await process_frame


func _test_stops_and_resumes() -> void:
	var runner := await _parked_runner()
	var car := runner.car
	var path := _path(at(90.0), at(-30.0))
	var agent := _agent(path, 8.0)
	var kinds: Array[StringName] = []
	agent.reacted.connect(func(kind: StringName, _cause: Node3D) -> void: kinds.append(kind))
	await frames(900)
	var gap := agent.global_position.z - car.global_position.z
	expect(agent.reaction == &"stopped" and is_zero_approx(agent.current_speed),
		"an agent stops behind the car standing in its lane")
	expect(gap > 4.2 + 0.5 and gap < 4.2 + agent.min_gap + 1.0,
		"it stops a little more than its minimum gap behind, without contact (%.2f m apart)" % gap)
	expect(kinds.has(&"following") and kinds.back() == &"stopped",
		"it reports following, then stopping: %s" % [kinds])

	car.global_position.x = -20.0
	await frames(300)
	expect(agent.reaction.is_empty() and is_equal_approx(agent.current_speed, agent.speed)
		and kinds.back() == &"resumed", "once the way is clear it resumes its scripted speed")
	await _cleanup([agent, path, runner])


func _test_forced_braking() -> void:
	var runner := await _parked_runner()
	var car := runner.car
	car.global_position.x = -20.0
	var path := _path(at(90.0), at(-30.0))
	var agent := _agent(path, 12.0)
	var braked := []
	agent.forced_to_brake.connect(func(cause: Node3D, decel: float) -> void:
		braked.append([cause, decel]))
	await frames(120)
	expect(braked.is_empty() and agent.reaction.is_empty(),
		"on a clear road the agent keeps its script and brakes for nothing")
	# The car cuts in 20 m ahead of the agent's centre, 16 m from its front: room to stop, but
	# only by braking hard.
	car.global_position = Vector3(1.75, 0, agent.global_position.z - 20.0)
	await frames(30)
	expect(braked.size() == 1 and braked[0][0] == car and braked[0][1] > agent.hard_brake,
		"a car cutting in close ahead forces it to brake hard, once, naming the car")
	await frames(240)
	var gap := agent.global_position.z - car.global_position.z
	expect(gap > 4.2, "and it stops without running into the car (%.2f m apart)" % gap)
	await _cleanup([agent, path, runner])


func _test_walker_waits() -> void:
	var runner := await _parked_runner()
	var car := runner.car
	var walk := _path(Vector3(-5, 0, car.global_position.z), Vector3(9, 0, car.global_position.z))
	var walker := _agent(walk, 1.4, true)
	await frames(360)
	expect(walker.reaction == &"stopped" and walker.global_position.x < car.global_position.x - 0.9,
		"a walker waits before a car standing on its way (at x %.2f)" % walker.global_position.x)
	car.global_position.x = -20.0
	await frames(600)
	expect(walker.is_done(), "and walks on once the car has gone")
	await _cleanup([walker, walk, runner])


## Positions of three agents queuing behind the car after a fixed number of ticks.
func _queue_positions() -> PackedFloat32Array:
	var runner := await _parked_runner()
	var nodes: Array = [runner]
	var agents: Array[ScriptedAgent] = []
	for i in 3:
		var path := _path(at(90.0 + i * 15.0), at(-30.0))
		var agent := _agent(path, 9.0 + i)
		agents.append(agent)
		nodes += [agent, path]
	await frames(900)
	var out := PackedFloat32Array()
	for agent in agents:
		out.append(agent.global_position.z)
	await _cleanup(nodes)
	return out


func _test_reproducible() -> void:
	var first := await _queue_positions()
	var second := await _queue_positions()
	expect(first == second, "the same traffic reacts the same way every time %s" % [first])
	expect(first[0] < first[1] and first[1] < first[2],
		"agents queue in order behind the car %s" % [first])
