extends TestCase
## The traffic pipeline on worker threads: road users thinking in parallel react exactly as they do
## thinking one after another on the main thread; and a road user and a parked car added to a
## running attempt are baked into its world, the car seen as soon as it stands.

const BUSY := preload("res://scenarios/scenes/busy_junction/busy_junction.tscn")
const PARKED_CAR := preload("res://scenarios/kit/parked_car.tscn")


func run() -> void:
	await _test_parallel_matches_inline()
	await _test_added_during_attempt()


## The reactions of the busy junction's clean drive, with where each road user stood, thinking in
## parallel or not.
func _busy_log(parallel: bool) -> Array:
	var log := []
	var count := [0]
	var on_spawn := func(runner: ExamRunner) -> void:
		runner.traffic.parallel = parallel
		var world := runner.world()
		runner.world_runner.events_emitted.connect(func(events: Array[WorldEvent]) -> void:
			for event in events:
				if event.kind == &"reacted":
					var position: Vector3 = world.get_value(Schema.AGENT, event.entity, &"position")
					log.append("%s %s %.2f" % [world.get_value(Schema.AGENT, event.entity, &"name"),
						event.data.kind, position.z]))
	var on_end := func(runner: ExamRunner) -> void:
		count[0] = runner.traffic.count
	await drive([{to = at(9.0), speed = 8.0}, {to = at(-35.0), speed = 8.0}, {wait = 9.0},
		{to = at(-110.0), speed = 8.0}], BUSY, on_spawn, on_end)
	expect(count[0] >= TrafficPipeline.PARALLEL_FROM,
		"the busy junction has enough road users to think in parallel (%d)" % count[0])
	return log


func _test_parallel_matches_inline() -> void:
	var inline := await _busy_log(false)
	var parallel := await _busy_log(true)
	expect(inline.size() > 20 and inline == parallel,
		"thinking on worker threads gives exactly the reactions of thinking inline (%d)"
		% parallel.size())


func _test_added_during_attempt() -> void:
	var runner := spawn_runner()
	runner.car.input_enabled = false
	await process_frame
	var lane := Path3D.new()
	lane.curve = Curve3D.new()
	lane.curve.add_point(Vector3(30, 0, 60))
	lane.curve.add_point(Vector3(30, 0, -60))
	runner.scenario.add_child(lane)
	var agent := ScriptedAgent.new()
	agent.name = "Latecomer"
	agent.path = lane
	agent.speed = 8.0
	var id := runner.add_road_user(agent)
	await frames(60)
	expect(id != 0 and agent_state(runner, &"Latecomer").state == AgentTable.State.MOVING,
		"a road user added during the attempt is baked into the world and drives")
	var van: StaticBody3D = PARKED_CAR.instantiate()
	runner.scenario.add_child(van)
	van.global_position = Vector3(30, 0.75, 0)
	runner.add_obstacle(van)
	await frames(900)
	var a := agent_state(runner, &"Latecomer")
	var gap: float = a.position.z - van.global_position.z
	expect(a.reaction == &"stopped" and gap > 4.2 and gap < 4.2 + a.min_gap + 1.0,
		"a parked car added during the attempt stops the road user behind it (%.2f m apart)" % gap)
	runner.queue_free()
	await process_frame
