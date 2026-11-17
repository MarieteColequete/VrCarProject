extends TestCase
## Throughput of the per-tick detection work: marking crossings and overlaps for 40,000 wheel
## moves over 40 lines, and 10,000 probe footprints. Runs only with TESTS_FILTER=bench and prints
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
