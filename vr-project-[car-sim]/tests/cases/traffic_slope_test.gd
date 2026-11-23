extends TestCase
## Road users on lanes that climb: the vehicle core slows uphill by gravity's share along the car
## ([PlanarVehicle]), a road user on a climbing lane reports the lane's grade ([AgentTable]) and
## is drawn and given its body pitched with it ([TrafficView]), and on flat lanes nothing changes.
## Run on hand-stepped simulations.

## The climb: 10 m up over 100 m along the ground, a 10% grade.
const RUN := 100.0
const RISE := 10.0


func run() -> void:
	_test_core()
	_test_lane_grade()
	_test_view()
	_test_flat()


func _test_core() -> void:
	var spec := (load("res://scenarios/vehicle/specs/saloon.tres") as CarSpec).packed()
	var grade := RISE / Vector2(RUN, RISE).length()
	var flat := Vector3(12.0, 0.0, 0.0)
	var up := flat
	var seconds := 3.0
	for i in int(seconds / DT):
		flat = PlanarVehicle.step(spec, flat, 0.0, 20.0, 1.0, DT)
		up = PlanarVehicle.step(spec, up, 0.0, 20.0, 1.0, DT, grade)
	var lost := flat.x - up.x
	var expected := CarSpec.G * grade * seconds
	expect(absf(lost - expected) < expected * 0.15,
		"on full drive uphill it ends slower than on the flat by the grade's pull: %.2f m/s, about %.2f"
		% [lost, expected])

	var plain := PlanarVehicle.step(spec, Vector3(9.0, 0.3, 0.1), 0.05, 1.0, 1.0, DT)
	var zero := PlanarVehicle.step(spec, Vector3(9.0, 0.3, 0.1), 0.05, 1.0, 1.0, DT, 0.0)
	expect(plain == zero, "a grade of 0 is the flat ground, exactly")

	var lorry: PackedFloat64Array = TrafficSpecs.all()[TrafficSpecs.LORRY]
	var crawl := Vector3.ZERO
	for i in 600:
		crawl = PlanarVehicle.step(lorry, crawl, 0.0, 2.0, 1.0, DT, grade)
	expect(crawl.x > 0.5, "a lorry still climbs the 10%%, if slowly: %.1f m/s after 10 s" % crawl.x)

	var held := Vector3.ZERO
	for i in 60:
		held = PlanarVehicle.step(lorry, held, 0.0, 0.0, 1.0, DT, 0.3)
	expect(held.x == 0.0, "standing on a climb, it does not roll back")


## A straight lane towards -Z, climbing [constant RISE] over [constant RUN] when [param climbs].
func _lane(runner: WorldRunner, climbs: bool, x := 0.0) -> LaneData:
	var points := PackedVector3Array()
	for k in 101:
		var along := k * RUN / 100.0
		points.append(Vector3(x, along * RISE / RUN if climbs else 0.0, -along))
	return Simulation.add_path(runner.world, points, {is_lane = true})


func _test_lane_grade() -> void:
	var runner := sim()
	var lane := _lane(runner, true)
	var flat_lane := _lane(runner, false, 20.0)
	# Fast enough that its engine cannot hold the speed up the climb.
	var lorry := {speed = 30.0, body_size = Vector3(2.5, 3.5, 10.0)}
	var climber := road_user(runner, lane, lorry)
	var level := road_user(runner, flat_lane, lorry)
	var expected := RISE / Vector2(RUN, RISE).length()
	var worst := 0.0
	var off_ground := 0.0
	var up_speed := 0.0
	var flat_speed := 0.0
	for i in 240:
		tick(runner)
		var a := state_of(runner, climber)
		if up_speed == 0.0 and a.progress > RUN * 0.8:
			up_speed = a.current_speed
			flat_speed = state_of(runner, level).current_speed
		if a.progress > 1.0 and a.progress < RUN - 1.0:
			worst = maxf(worst, absf(a.grade - expected))
			off_ground = maxf(off_ground, absf(a.position.y + a.position.z * RISE / RUN))
	expect(worst < 0.002, "a road user on a climbing lane reports its grade, %.4f, within %.4f"
		% [expected, worst])
	expect(off_ground < 0.05, "and stands on the lane, within %.3f m of it" % off_ground)
	expect(up_speed > 0.0 and up_speed < flat_speed - 0.5,
		"a lorry slows up the climb, where its engine cannot hold the speed: %.1f m/s against %.1f"
		% [up_speed, flat_speed])
	end_sim(runner)


func _test_view() -> void:
	var runner := sim()
	var lane := _lane(runner, true)
	var car := road_user(runner, lane, {speed = 10.0})
	var walker := road_user(runner, _lane(runner, true, 20.0), {pedestrian = true, speed = 1.4,
		body_size = Vector3(0.5, 1.8, 0.5)})
	tick(runner, 120)
	var holder := Node3D.new()
	root.add_child(holder)
	var view := TrafficView.new(holder, 4)
	view.draw(runner.world)
	var a := state_of(runner, car)
	var grade: float = a.grade
	var key := TrafficView.model_for(car, a.body_size, false)
	var group: Dictionary = view._groups[key]
	# The buffer last handed to the multimesh (the headless renderer keeps none to read back).
	var buffer: PackedFloat32Array = group.previous
	var k: int = group.slots[car] * TrafficView.STRIDE
	var drawn := Transform3D(Vector3(buffer[k], buffer[k + 4], buffer[k + 8]),
		Vector3(buffer[k + 1], buffer[k + 5], buffer[k + 9]),
		Vector3(buffer[k + 2], buffer[k + 6], buffer[k + 10]),
		Vector3(buffer[k + 3], buffer[k + 7], buffer[k + 11]))
	var forward := -drawn.basis.z.normalized()
	var up := drawn.basis.y.normalized()
	expect(grade > 0.09 and absf(forward.y - grade) < 0.001,
		"a car on the climb is drawn nose up by the lane's grade: %.4f against %.4f"
		% [forward.y, grade])
	expect(absf(up.dot(forward)) < 0.0001 and absf(drawn.basis.x.normalized().y) < 0.0001,
		"pitched about its own right axis, the right axis level")
	expect(drawn.basis.y.length() > a.body_size.y - 0.001
		and drawn.basis.z.length() > a.body_size.z - 0.001,
		"and not shortened by the pitch")
	# The transform handed to the physics server for its kinematic box.
	var box: Transform3D = (view._bodies[car] as Array)[2]
	expect(absf(-box.basis.z.y - grade) < 0.001 and box.origin.is_equal_approx(a.position),
		"its physics box pitches the same way, where it stands")
	var man := view.walker(walker)
	if man:
		expect(man.basis.y.is_equal_approx(Vector3.UP), "a walker on the climb stays upright")
	view.clear()
	holder.queue_free()
	end_sim(runner)


## On a flat lane, as before the grade: grade 0 throughout, the car drawn and boxed level, and the
## same drive, exactly, as a fingerprint printed for comparison with the code before it.
func _test_flat() -> void:
	var runner := sim()
	var lane := _lane(runner, false)
	var car := road_user(runner, lane, {speed = 14.0})
	var graded := false
	for i in 300:
		tick(runner)
		graded = graded or state_of(runner, car).grade != 0.0
	expect(not graded, "on a flat lane the grade stays 0")
	var a := state_of(runner, car)
	var place := TrafficView.pitched(a.facing, 0.0, a.position)
	var f: Vector3 = a.facing
	var level := Basis(Vector3(-f.z, 0.0, f.x), Vector3.UP, Vector3(-f.x, 0.0, -f.z))
	expect(place.basis.is_equal_approx(level), "and is drawn level, as before")
	end_sim(runner)
	if OS.get_environment("TESTS_FINGERPRINT") != "":
		print("flat fingerprint: ", _flat_fingerprint())


## Every bit of a drive through a flat bend: the dynamic columns, tick by tick, hashed.
func _flat_fingerprint() -> String:
	var runner := sim()
	var points := PackedVector3Array()
	for k in 41:
		points.append(Vector3(0.0, 0.0, -k * 0.5))
	for k in range(1, 61):
		var angle := k / 60.0 * PI * 0.5
		points.append(Vector3(-30.0 + 30.0 * cos(angle), 0.0, -20.0 - 30.0 * sin(angle)))
	var lane := Simulation.add_path(runner.world, points, {is_lane = true})
	var car := road_user(runner, lane, {speed = 16.0})
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for i in 400:
		tick(runner)
		var a := state_of(runner, car)
		ctx.update(var_to_bytes([a.progress, a.current_speed, a.lateral, a.heading,
			a.side_speed, a.yaw_rate, a.steer, a.position, a.facing]))
	end_sim(runner)
	return ctx.finish().hex_encode()
