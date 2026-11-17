extends TestCase
## Throughput of the per-tick detection work: marking crossings and overlaps for 40,000 wheel
## moves over 40 lines, 10,000 probe footprints, and the traffic system's main thread cost with
## 200 road users, thinking inline and in parallel. Runs only with TESTS_FILTER=bench and prints
## its timings; the counts it asserts keep the work from being optimised away unnoticed.


func run() -> void:
	if not OS.get_environment("TESTS_FILTER").contains("bench"):
		return
	var markings: Array[RoadMarking] = []
	var index := MarkingIndex.new()
	for i in 40:
		var marking := RoadMarking.new()
		marking.kind = RoadMarking.Kind.DASHED
		marking.curve = Curve3D.new()
		marking.curve.add_point(Vector3(i * 3.5, 0, 0))
		marking.curve.add_point(Vector3(i * 3.5, 0, -200))
		root.add_child(marking)
		markings.append(marking)
		index.add(marking)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var moves: Array[PackedVector3Array] = []
	for i in 40000:
		var p := Vector3(rng.randf_range(0, 140), 0, rng.randf_range(-200, 0))
		moves.append(PackedVector3Array([p, p + Vector3(rng.randf_range(-0.3, 0.3), 0,
			rng.randf_range(-0.3, 0.3))]))
	var start := Time.get_ticks_usec()
	var hits := 0
	for move in moves:
		hits += index.crossings(move[0], move[1]).size()
	var crossed := Time.get_ticks_usec()
	for move in moves:
		index.overlapping(move[0], 0.1)
	var overlapped := Time.get_ticks_usec()
	print("bench: %d crossings in %.1f ms, %d overlaps in %.1f ms" % [moves.size(),
		(crossed - start) / 1000.0, moves.size(), (overlapped - crossed) / 1000.0])
	expect(hits > 0, "the benchmark's moves cross lines (%d hits)" % hits)
	for marking in markings:
		marking.free()

	var runner := spawn_runner()
	await process_frame
	var probe := runner.session.probe
	start = Time.get_ticks_usec()
	for i in 10000:
		runner.car.global_position.x += 0.001
		probe.wheels()
		probe.corners()
		probe.forward()
	print("bench: 10000 footprints in %.1f ms" % [(Time.get_ticks_usec() - start) / 1000.0])
	expect(probe.wheels().size() == 4, "the probe gives four wheels")

	runner.queue_free()
	await process_frame
	await _bench_traffic()


## The traffic system's cost on the main thread with 200 reactive road users: ten looping lanes
## of 20 cars, each lane with a cycling light so queues form and clear, timed after a warm-up that
## spreads them out. Thinking in parallel and inline are compared; the headless run has no frame
## to overlap the thinking with, so the time the main thread waits for it is reported apart.
func _bench_traffic() -> void:
	for parallel in [false, true]:
		var t := await _traffic_times(200, parallel)
		print(("bench: 200 road users, %s: snapshot %.3f ms, apply %.3f ms, waiting %.3f ms, "
			+ "physics tick %.3f ms") % ["parallel" if parallel else "inline", t[0], t[1], t[2], t[3]])
		expect(t[3] > 0.0, "the traffic benchmark measured its ticks (%s)"
			% ("parallel" if parallel else "inline"))


## Mean milliseconds per tick: taking the snapshot (and thinking, when inline), applying the
## decisions, waiting for threads, and the whole physics process.
func _traffic_times(count: int, parallel: bool) -> PackedFloat64Array:
	var runner := spawn_runner()
	runner.car.input_enabled = false
	await process_frame
	var nodes: Array[Node] = [runner]
	var system: TrafficSystem
	for l in 10:
		var x := 40.0 + l * 4.0
		var light := TrafficLight.new()
		light.red_time = 6.0 + l * 0.3
		light.green_time = 8.0
		light.draw_lamps = false
		root.add_child(light)
		nodes.append(light)
		var lane := TrafficLane.new()
		lane.curve = Curve3D.new()
		lane.curve.add_point(Vector3(x, 0, 200))
		lane.curve.add_point(Vector3(x, 0, -200))
		lane.light = light
		lane.stop_offset = 200.0
		root.add_child(lane)
		nodes.append(lane)
		for i in count / 10:
			var agent := ScriptedAgent.new()
			agent.path = lane
			agent.speed = 10.0 + (i % 3)
			agent.loop = true
			agent.start_delay = i * 1.6
			root.add_child(agent)
			nodes.append(agent)
			system = TrafficSystem.of(agent)
	system.parallel = parallel
	await frames(40 * 60)
	var sums := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var ticks := 600
	for t in ticks:
		await physics_frame
		sums[0] += system.think_usec / 1000.0
		sums[1] += (system.commit_usec - system.wait_usec) / 1000.0
		sums[2] += system.wait_usec / 1000.0
		sums[3] += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	system.parallel = true
	for node in nodes:
		node.queue_free()
	await process_frame
	for i in 4:
		sums[i] /= ticks
	return sums
