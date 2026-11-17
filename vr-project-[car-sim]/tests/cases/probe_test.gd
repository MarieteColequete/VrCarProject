extends TestCase
## The vehicle probe: footprint, wheel movement, gaze, and direction changes.


func run() -> void:
	await _test_probe()


func _test_probe() -> void:
	var runner := spawn_runner()
	var car: Node3D = runner.car
	car.input_enabled = false
	var probe := VehicleProbe.of(car)
	car.look_at(car.global_position + Vector3(-1, 0, 0), Vector3.UP)
	await physics_frame
	var fwd := probe.forward()
	var right := fwd.cross(Vector3.UP)
	var expected_fl := car.global_position + fwd * probe.body_length * 0.5 - right * probe.body_width * 0.5
	expect(probe.corners()[0].is_equal_approx(expected_fl), "the front left corner follows the car's heading")
	expect(probe.wheels()[2].is_equal_approx(
		car.global_position - fwd * probe.wheelbase * 0.5 + right * probe.track * 0.5),
		"the rear right wheel sits at half the wheelbase and track")
	car.global_position += Vector3(-0.5, 0, 0)
	await physics_frame
	await physics_frame
	var moved := probe.wheels()[0] - probe.previous_wheels()[0]
	expect(moved.is_zero_approx(), "wheels at rest have no movement this tick")
	car.global_position += Vector3(-0.2, 0, 0)
	await physics_frame
	moved = probe.wheels()[0] - probe.previous_wheels()[0]
	expect(moved.is_equal_approx(Vector3(-0.2, 0, 0)), "a wheel's movement this tick is the car's step")

	var view: DriverView = car.driver_view
	view.turn(0.5, 0.0)
	expect(probe.look_direction().is_equal_approx(view.look_direction())
		and not probe.look_direction().is_equal_approx(probe.forward()),
		"the probe looks where the driver view looks")
	runner.queue_free()
	await process_frame

	var changes := [0]
	var r := await drive([
		{to = at(40.0), speed = 4.0}, {wait = 0.5},
		{to = at(43.0), speed = 2.0, reverse = true}, {wait = 0.5},
		{to = at(38.0), speed = 4.0}],
		null, Callable(), func(done: ExamRunner) -> void:
			changes[0] = VehicleProbe.of(done.car).direction_changes)
	expect(changes[0] == 2, "forward, reverse, forward is two direction changes (got %d)" % changes[0])
	expect(r.reason == &"aborted", "a manoeuvre short of the goal ends aborted: " + r.summary())
