extends TestCase
## Road users driving on the shared vehicle core ([PlanarVehicle] through [AgentTable]): a car
## slows ahead of a bend to what it takes it at and keeps its lane through it, each road user
## drives the spec its size picks ([TrafficSpecs]), and the lane's curvature is read the right way
## round. Run on hand-stepped simulations.

const RADIUS := 25.0


func run() -> void:
	_test_curvature()
	_test_specs()
	_test_bend()


## A straight run of 60 m towards -Z, then a quarter circle to the left, then 60 m on.
func _bend_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	for k in 121:
		points.append(Vector3(0.0, 0.0, -k * 0.5))
	var centre := Vector3(-RADIUS, 0.0, -60.0)
	for k in range(1, 81):
		var a := k / 80.0 * PI * 0.5
		points.append(centre + Vector3(RADIUS * cos(a), 0.0, -RADIUS * sin(a)))
	var end := points[points.size() - 1]
	for k in range(1, 121):
		points.append(end + Vector3(-k * 0.5, 0.0, 0.0))
	return points


func _test_curvature() -> void:
	var runner := sim()
	var lane := Simulation.add_path(runner.world, _bend_points(), {is_lane = true})
	var samples := RouteTable.curvature_of(lane)
	var middle := samples[int(60.0 + RADIUS * PI * 0.25)]
	expect(absf(samples[20]) < 0.002, "a straight lane does not curve: %.4f" % samples[20])
	expect(absf(middle - 1.0 / RADIUS) < 0.006,
		"a bend to the left curves positive, one over its radius: %.4f" % middle)
	end_sim(runner)


func _test_specs() -> void:
	expect(TrafficSpecs.pick(Vector3(1.8, 1.4, 4.2)) == TrafficSpecs.HATCHBACK
		and TrafficSpecs.pick(Vector3(1.9, 1.5, 4.9)) == TrafficSpecs.SALOON
		and TrafficSpecs.pick(Vector3(2.0, 2.4, 6.0)) == TrafficSpecs.VAN
		and TrafficSpecs.pick(Vector3(2.5, 3.5, 10.0)) == TrafficSpecs.LORRY,
		"a road user drives the car its size picks")
	expect(TrafficSpecs.all().size() == TrafficSpecs.PATHS.size(), "every spec packs")


func _test_bend() -> void:
	var runner := sim()
	var lane := Simulation.add_path(runner.world, _bend_points(), {is_lane = true})
	var agent := road_user(runner, lane, {speed = 15.0})
	var fastest := 0.0
	var slowest_in_bend := INF
	var widest := 0.0
	for i in 900:
		tick(runner)
		var a := state_of(runner, agent)
		if a.state == AgentTable.State.DONE:
			break
		var into: float = a.progress - 60.0
		if into < -5.0:
			fastest = maxf(fastest, a.current_speed)
		elif into > 5.0 and into < RADIUS * PI * 0.5 - 5.0:
			slowest_in_bend = minf(slowest_in_bend, a.current_speed)
		widest = maxf(widest, absf(a.lateral))
	var through := PlanarVehicle.curve_speed(1.0 / RADIUS, 3.5)
	expect(fastest > 12.0, "on the straight it gets up to speed: %.1f m/s" % fastest)
	expect(slowest_in_bend < through + 0.6 and slowest_in_bend > through - 3.0,
		"it takes the bend at about %.1f m/s: %.1f" % [through, slowest_in_bend])
	expect(widest < 0.6, "and keeps its lane, within %.2f m of it" % widest)
	var done := state_of(runner, agent)
	expect(done.state == AgentTable.State.DONE, "and drives the path to its end")
	end_sim(runner)
