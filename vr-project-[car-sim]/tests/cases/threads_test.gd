extends TestCase
## The traffic system on worker threads: road users thinking in parallel react exactly as they do
## thinking one after another on the main thread, and a parked car added during an attempt is
## seen as soon as it stands.

const BUSY := preload("res://scenarios/scenes/busy_junction/busy_junction.tscn")
const PARKED_CAR := preload("res://scenarios/kit/parked_car.tscn")

var _log: PackedStringArray = []


func run() -> void:
	await _test_parallel_matches_inline()
	await _test_new_obstacle_seen()


func _hook(node: Node) -> void:
	if node is ScriptedAgent:
		var agent := node as ScriptedAgent
		agent.reacted.connect(func(kind: StringName, _cause: Node3D) -> void:
			_log.append("%s %s %.2f" % [agent.name, kind, agent.global_position.z]))


## The reactions of the busy junction's clean drive, thinking in parallel or not.
func _busy_log(parallel: bool) -> PackedStringArray:
	_log = PackedStringArray()
	var count := [0]
	var on_spawn := func(runner: ExamRunner) -> void:
		var system := TrafficSystem.of(runner.scenario)
		system.parallel = parallel
		runner.get_tree().node_added.connect(_hook)
		for node in runner.scenario.find_children("*", "", true, false):
			_hook(node)
	var on_end := func(runner: ExamRunner) -> void:
		runner.get_tree().node_added.disconnect(_hook)
		count[0] = TrafficSystem.of(runner.scenario).count()
		TrafficSystem.of(runner.scenario).parallel = true
	await drive([{to = at(9.0), speed = 8.0}, {to = at(-35.0), speed = 8.0}, {wait = 9.0},
		{to = at(-110.0), speed = 8.0}], BUSY, on_spawn, on_end)
	expect(count[0] >= TrafficSystem.PARALLEL_FROM,
		"the busy junction has enough road users to think in parallel (%d)" % count[0])
	return _log.duplicate()


func _test_parallel_matches_inline() -> void:
	var inline := await _busy_log(false)
	var parallel := await _busy_log(true)
	expect(inline.size() > 20 and inline == parallel,
		"thinking on worker threads gives exactly the reactions of thinking inline (%d)"
		% parallel.size())


func _test_new_obstacle_seen() -> void:
	var runner := spawn_runner()
	runner.car.input_enabled = false
	var lane := Path3D.new()
	lane.curve = Curve3D.new()
	lane.curve.add_point(Vector3(30, 0, 60))
	lane.curve.add_point(Vector3(30, 0, -60))
	runner.scenario.add_child(lane)
	var agent := ScriptedAgent.new()
	agent.path = lane
	agent.speed = 8.0
	runner.scenario.add_child(agent)
	await frames(60)
	var van: StaticBody3D = PARKED_CAR.instantiate()
	runner.scenario.add_child(van)
	van.global_position = Vector3(30, 0.75, 0)
	await frames(900)
	var gap := agent.global_position.z - van.global_position.z
	expect(agent.reaction == &"stopped" and gap > 4.2 and gap < 4.2 + agent.min_gap + 1.0,
		"a parked car added during the attempt stops the road user behind it (%.2f m apart)" % gap)
	runner.queue_free()
	await process_frame
