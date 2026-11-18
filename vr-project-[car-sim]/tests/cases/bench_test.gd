extends TestCase
## Throughput of the per-tick work: marking crossings and overlaps for 40,000 wheel moves over 40
## lines, 10,000 vehicle motion steps, and the traffic pipeline's main thread cost with 200 road
## users, thinking inline and in parallel. Runs only with TESTS_FILTER=bench and prints its
## timings; the counts it asserts keep the work from being optimised away unnoticed.


func run() -> void:
	if not OS.get_environment("TESTS_FILTER").contains("bench"):
		return
	var index := MarkingIndex.new()
	for i in 40:
		var points := PackedVector3Array([Vector3(i * 3.5, 0, 0), Vector3(i * 3.5, 0, -200)])
		var curve := Curve3D.new()
		for p in points:
			curve.add_point(p)
		index.add(i + 1, RoadMarking.Kind.DASHED, 0.06, curve.get_baked_points())
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

	var world := World.new()
	Simulation.empty_world(world)
	var car := world.spawn({vehicle = {}})
	var row := {}
	for column: StringName in world.store(Schema.VEHICLE).columns:
		row[column] = world.get_value(Schema.VEHICLE, car, column)
	start = Time.get_ticks_usec()
	var out := {}
	for i in 10000:
		row.transform = Transform3D(Basis(), Vector3(i * 0.001, 0, 0))
		out = VehicleLogic.step(row, DT)
		row.merge(out, true)
	print("bench: 10000 vehicle steps in %.1f ms" % [(Time.get_ticks_usec() - start) / 1000.0])
	expect((out.wheels as PackedVector3Array).size() == 4, "a vehicle step gives four wheels")
	_bench_traffic()


## The traffic pipeline's cost on the main thread with 200 reactive road users: ten looping lanes
## of 20 cars, each lane with a cycling light so queues form and clear, timed after a warm-up that
## spreads them out. Thinking in parallel and inline are compared; the headless run has no frame
## to overlap the thinking with, so the time the main thread waits for it is reported apart.
func _bench_traffic() -> void:
	for parallel in [false, true]:
		var t := _traffic_times(200, parallel)
		print(("bench: 200 road users, %s: snapshot %.3f ms, commit %.3f ms, waiting %.3f ms, "
			+ "tick %.3f ms") % ["parallel" if parallel else "inline", t[0], t[1], t[2], t[3]])
		expect(t[3] > 0.0, "the traffic benchmark measured its ticks (%s)"
			% ("parallel" if parallel else "inline"))


## Mean milliseconds per tick: taking the snapshot (and thinking, when inline), committing the
## decisions, waiting for threads, and the whole tick.
func _traffic_times(count: int, parallel: bool) -> PackedFloat64Array:
	var s := WorldRunner.new()
	Simulation.empty_world(s.world)
	var traffic := Simulation.add_systems(s, false)
	traffic.parallel = parallel
	for l in 10:
		var x := 40.0 + l * 4.0
		var values := {mode = TrafficLight.Mode.CYCLE, initial = TrafficLight.Light.RED,
			red_time = 6.0 + l * 0.3, red_amber_time = 1.0, green_time = 8.0, amber_time = 3.0}
		values.merge(LightLogic.initial(values), true)
		var light := s.world.spawn({light = values})
		var lane := path(s, Vector3(x, 0, 200), Vector3(x, 0, -200),
			{is_lane = true, light = light, stop_at = 200.0})
		for i in count / 10:
			road_user(s, lane, {speed = 10.0 + (i % 3), loop = true, start_delay = i * 1.6})
	tick(s, 40 * 60)
	var sums := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var ticks := 600
	for t in ticks:
		var started := Time.get_ticks_usec()
		tick(s)
		sums[0] += traffic.think_usec / 1000.0
		sums[1] += (traffic.commit_usec - traffic.wait_usec) / 1000.0
		sums[2] += traffic.wait_usec / 1000.0
		sums[3] += (Time.get_ticks_usec() - started) / 1000.0
	end_sim(s)
	for i in 4:
		sums[i] /= ticks
	return sums
