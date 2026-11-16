extends SceneTree
## Headless tests of the scenario system. Run from the repository root:
##   godot --headless --path 'vr-project-[car-sim]' -s res://tests/run_tests.gd
## Exits 0 when every test passes, 1 otherwise. Drives move the car along fixed legs, one step
## per physics tick, so results do not depend on the machine's speed.

const RUNNER := preload("res://scenarios/scenes/exam_runner.tscn")
const POLICY := preload("res://scenarios/data/default_policy.tres")
const FAULTS := "res://scenarios/data/faults/%s.tres"
const STEPS_FIXTURE := preload("res://tests/fixtures/steps_fixture.tscn")

## Lane centre and the stop junction's key positions along it (the car drives towards -Z).
const LANE_X := 1.75
const STOP_AT := 7.2

var _failed := 0
var _passed := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_scoring()
	_test_bindings()
	_test_driver_input()
	await _test_driver_view()
	await _test_debug_car_controls()
	await _test_drives()
	await _test_probe()
	await _test_session()
	print("\n%d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _expect(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
	else:
		_failed += 1
		printerr("FAIL: ", what)


# --- Scoring -------------------------------------------------------------------------------------

func _faults(ids: Array) -> Array[FaultRecord]:
	var list: Array[FaultRecord] = []
	for id in ids:
		list.append(FaultRecord.new(load(FAULTS % id), 0.0, Vector3.ZERO))
	return list


func _test_scoring() -> void:
	var minors := []
	for i in 9:
		minors.append("lane_drift")
	_expect(POLICY.evaluate(_faults([])).passed, "no faults pass")
	_expect(POLICY.evaluate(_faults(minors)).passed, "nine minor faults pass")
	_expect(not POLICY.evaluate(_faults(minors + ["lane_drift"])).passed, "ten minor faults fail")
	_expect(POLICY.evaluate(_faults(["off_route"])).passed, "one serious fault passes")
	var two_serious := POLICY.evaluate(_faults(["off_route", "speeding_serious"]))
	_expect(not two_serious.passed and two_serious.failing_tier == &"serious",
		"two serious faults fail on the serious tier")
	var critical := POLICY.evaluate(_faults(["stop_not_made"]))
	_expect(not critical.passed and critical.failing_tier == &"critical",
		"one critical fault fails on the critical tier")
	var unknown := FaultDef.new()
	unknown.id = &"test_unknown"
	unknown.tier = &"no_such_tier"
	var with_unknown: Array[FaultRecord] = [FaultRecord.new(unknown, 0.0, Vector3.ZERO)]
	_expect(not POLICY.evaluate(with_unknown).passed, "a fault of an unknown tier fails")


# --- Controls and camera -------------------------------------------------------------------------

func _has_event(action: StringName, type: String) -> bool:
	for event in InputMap.action_get_events(action):
		if event.is_class(type):
			return true
	return false


func _test_bindings() -> void:
	for action in DriverInput.CAR_ACTIONS + [&"look_reset", &"toggle_view"]:
		_expect(InputMap.has_action(action) and _has_event(action, "InputEventKey")
			and (_has_event(action, "InputEventJoypadMotion")
				or _has_event(action, "InputEventJoypadButton")),
			"%s is bound on the keyboard and the gamepad" % action)
	for action in [&"look_left", &"look_right", &"look_up", &"look_down"]:
		_expect(InputMap.has_action(action) and _has_event(action, "InputEventJoypadMotion"),
			"%s is bound to a gamepad stick" % action)
	_expect(InputMap.has_action(&"release_mouse") and _has_event(&"release_mouse", "InputEventKey"),
		"release_mouse is bound on the keyboard")


func _release_all() -> void:
	for action in DriverInput.CAR_ACTIONS:
		Input.action_release(action)


func _test_driver_input() -> void:
	Input.action_press(&"throttle", 0.5)
	_expect(is_equal_approx(DriverInput.throttle(), 0.5), "half trigger is half throttle")
	Input.action_press(&"brake")
	_expect(is_equal_approx(DriverInput.brake(), 1.0), "a brake key is full brake")
	Input.action_press(&"steer_left")
	_expect(is_equal_approx(DriverInput.steer(), 1.0), "steer_left alone is full left")
	Input.action_press(&"steer_right")
	_expect(is_zero_approx(DriverInput.steer()), "both steer actions cancel out")
	Input.action_release(&"steer_left")
	_expect(is_equal_approx(DriverInput.steer(), -1.0), "steer_right alone is full right")
	_release_all()
	_expect(is_zero_approx(DriverInput.throttle() + DriverInput.brake() + DriverInput.steer()),
		"released controls are neutral")

	var q := InputEventKey.new()
	q.physical_keycode = KEY_Q
	q.pressed = true
	_expect(DriverInput.indicator_pressed(q) == VehicleProbe.Indicator.LEFT, "Q is the left indicator")
	var rb := InputEventJoypadButton.new()
	rb.button_index = JOY_BUTTON_RIGHT_SHOULDER
	rb.pressed = true
	_expect(DriverInput.indicator_pressed(rb) == VehicleProbe.Indicator.RIGHT,
		"RB is the right indicator")


func _test_driver_view() -> void:
	var view: DriverView = load("res://player/driver_view.tscn").instantiate()
	view.capture_mouse = false
	view.require_capture = false
	root.add_child(view)
	await process_frame
	_expect(not view.vr and view.flat_camera.current, "without a headset the flat camera is current")

	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(-100.0, 40.0)
	view._unhandled_input(motion)
	_expect(is_equal_approx(view.yaw, 100.0 * view.mouse_sensitivity)
		and is_equal_approx(view.pitch, -40.0 * view.mouse_sensitivity),
		"mouse motion turns the view by its sensitivity")
	_expect(view.look_direction().x < 0.0, "moving the mouse left looks left")

	motion.relative = Vector2(-100000.0, -100000.0)
	view._unhandled_input(motion)
	_expect(is_equal_approx(view.yaw, deg_to_rad(view.max_yaw_degrees))
		and is_equal_approx(view.pitch, deg_to_rad(view.max_pitch_degrees)),
		"the view stops at its yaw and pitch limits")

	Input.action_press(&"look_right")
	await process_frame
	await process_frame
	Input.action_release(&"look_right")
	_expect(view.yaw < deg_to_rad(view.max_yaw_degrees), "the right stick turns the view")

	view.reset_look()
	_expect(is_zero_approx(view.yaw) and is_zero_approx(view.pitch), "look_reset recentres")
	view.queue_free()
	await process_frame


func _test_debug_car_controls() -> void:
	var runner: ExamRunner = RUNNER.instantiate()
	runner.print_results = false
	root.add_child(runner)
	var car: Node3D = runner.car
	await physics_frame
	var start := car.global_position
	Input.action_press(&"throttle")
	for i in 60:
		await physics_frame
	Input.action_press(&"steer_left")
	for i in 30:
		await physics_frame
	_release_all()
	var moved := car.global_position - start
	_expect(car.current_speed > 0.0 and moved.z < -1.0, "throttle drives the car forward")
	_expect(moved.x < 0.0, "steer_left turns the car left")

	Input.action_press(&"brake")
	for i in 240:
		await physics_frame
	_release_all()
	_expect(car.current_speed < 0.0, "holding the brake stops the car, then reverses")

	var probe := VehicleProbe.of(car)
	Input.action_press(&"handbrake")
	await physics_frame
	await physics_frame
	_expect(probe.handbrake == VehicleProbe.Toggle.ON, "the handbrake reaches the probe")
	Input.action_release(&"handbrake")
	await physics_frame
	await physics_frame
	_expect(probe.handbrake == VehicleProbe.Toggle.OFF, "releasing the handbrake reaches the probe")

	car._unhandled_input(_action_event(&"toggle_view"))
	_expect(car.chase_camera.current and not car.driver_view.active, "toggle_view shows the chase camera")
	runner.queue_free()
	await process_frame


func _action_event(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


# --- Scripted drives through the stop junction ---------------------------------------------------

func _at(z: float, x := LANE_X) -> Vector3:
	return Vector3(x, 0.0, z)


## Legs of a drive: {to: Vector3, speed: m/s} moves in a straight line, facing the target, or
## facing away from it with reverse = true; {wait: s} stays put. [param on_spawn] is called
## with the runner once the car is placed, and [param on_end] just before it is freed.
func _drive(legs: Array, scenario: PackedScene = null, on_spawn := Callable(),
		on_end := Callable()) -> ScenarioResult:
	var runner: ExamRunner = RUNNER.instantiate()
	runner.print_results = false
	if scenario:
		runner.scenario_scene = scenario
	root.add_child(runner)
	if on_spawn.is_valid():
		on_spawn.call(runner)
	var car: Node3D = runner.car
	car.input_enabled = false
	var session := runner.session
	var dt := 1.0 / Engine.physics_ticks_per_second
	await physics_frame
	for leg: Dictionary in legs:
		if leg.has("wait"):
			var waited := 0.0
			while waited < leg.wait and session.is_running():
				await physics_frame
				waited += dt
			continue
		var target: Vector3 = leg.to
		while session.is_running() and car.global_position.distance_to(target) > 0.001:
			var pos := car.global_position
			var dir := target - pos
			dir.y = 0.0
			if dir.length() > 0.01:
				car.look_at(pos - dir if leg.get("reverse", false) else pos + dir, Vector3.UP)
			car.global_position = pos.move_toward(target, leg.speed * dt)
			await physics_frame
	for i in 60:
		if not session.is_running():
			break
		await physics_frame
	if session.is_running():
		session.abort()
	var result := session.result
	if on_end.is_valid():
		on_end.call(runner)
	runner.queue_free()
	await process_frame
	return result


func _test_drives() -> void:
	var r: ScenarioResult

	r = await _drive([
		{to = _at(STOP_AT), speed = 8.0}, {wait = 1.0}, {to = _at(-24.0), speed = 8.0}])
	_expect(r.reason == &"completed" and r.passed and r.faults.is_empty(),
		"clean drive passes with no faults: " + r.summary())

	r = await _drive([{to = _at(-24.0), speed = 8.0}])
	_expect(r.reason == &"eliminated" and not r.passed and r.has_fault(&"stop_not_made"),
		"rolling through the stop is eliminating: " + r.summary())

	r = await _drive([
		{to = _at(14.0), speed = 12.5}, {to = _at(STOP_AT), speed = 5.0}, {wait = 1.0},
		{to = _at(-24.0), speed = 8.0}])
	_expect(r.reason == &"completed" and r.count_tier(&"serious") == 1
		and r.has_fault(&"speeding_serious") and r.faults.size() == 1,
		"45 km/h in the 30 zone is one serious fault: " + r.summary())

	r = await _drive([
		{to = _at(40.0), speed = 8.0}, {to = _at(32.0, -0.5), speed = 8.0},
		{to = _at(20.0, -0.5), speed = 8.0}, {to = _at(14.0), speed = 8.0},
		{to = _at(STOP_AT), speed = 8.0}, {wait = 1.0}, {to = _at(-24.0), speed = 8.0}])
	_expect(r.reason == &"completed" and r.passed and r.has_fault(&"lane_drift")
		and r.faults.size() == 1,
		"drifting across the centre line is one lane fault: " + r.summary())

	r = await _drive([{to = _at(40.0), speed = 6.0}, {to = _at(27.5, 4.6), speed = 6.0}])
	_expect(r.reason == &"eliminated" and r.has_fault(&"contact_obstacle"),
		"hitting the parked car is eliminating: " + r.summary())

	r = await _drive([{to = _at(30.0), speed = 6.0}, {to = _at(42.0), speed = 5.0}])
	_expect(r.reason == &"eliminated" and r.has_fault(&"wrong_way"),
		"driving back against the lane is eliminating: " + r.summary())


# --- Probe: footprint, direction, live state, gaze -----------------------------------------------

func _test_probe() -> void:
	var runner: ExamRunner = RUNNER.instantiate()
	runner.print_results = false
	root.add_child(runner)
	var car: Node3D = runner.car
	car.input_enabled = false
	var probe := VehicleProbe.of(car)
	car.look_at(car.global_position + Vector3(-1, 0, 0), Vector3.UP)
	await physics_frame
	var fwd := probe.forward()
	var right := fwd.cross(Vector3.UP)
	var expected_fl := car.global_position + fwd * probe.body_length * 0.5 - right * probe.body_width * 0.5
	_expect(probe.corners()[0].is_equal_approx(expected_fl), "the front left corner follows the car's heading")
	_expect(probe.wheels()[2].is_equal_approx(
		car.global_position - fwd * probe.wheelbase * 0.5 + right * probe.track * 0.5),
		"the rear right wheel sits at half the wheelbase and track")
	car.global_position += Vector3(-0.5, 0, 0)
	await physics_frame
	await physics_frame
	var moved := probe.wheels()[0] - probe.previous_wheels()[0]
	_expect(moved.is_zero_approx(), "wheels at rest have no movement this tick")
	car.global_position += Vector3(-0.2, 0, 0)
	await physics_frame
	moved = probe.wheels()[0] - probe.previous_wheels()[0]
	_expect(moved.is_equal_approx(Vector3(-0.2, 0, 0)), "a wheel's movement this tick is the car's step")

	var view: DriverView = car.driver_view
	view.turn(0.5, 0.0)
	_expect(probe.look_direction().is_equal_approx(view.look_direction())
		and not probe.look_direction().is_equal_approx(probe.forward()),
		"the probe looks where the driver view looks")
	runner.queue_free()
	await process_frame

	var changes := [0]
	var r := await _drive([
		{to = _at(40.0), speed = 4.0}, {wait = 0.5},
		{to = _at(43.0), speed = 2.0, reverse = true}, {wait = 0.5},
		{to = _at(38.0), speed = 4.0}],
		null, Callable(), func(done: ExamRunner) -> void:
			changes[0] = VehicleProbe.of(done.car).direction_changes)
	_expect(changes[0] == 2, "forward, reverse, forward is two direction changes (got %d)" % changes[0])
	_expect(r.reason == &"aborted", "a manoeuvre short of the goal ends aborted: " + r.summary())


# --- Session: steps, check windows, dedupe, plain data -------------------------------------------

func _test_session() -> void:
	var step_titles: Array[String] = []
	var record_steps := func(runner: ExamRunner) -> void:
		runner.session.step_changed.connect(func(step: ScenarioStep) -> void:
			step_titles.append(step.title))

	var r := await _drive([{to = Vector3(0, 0, -45), speed = 8.0}], STEPS_FIXTURE, record_steps)
	_expect(r.reason == &"completed" and r.steps_completed == 2 and r.step_count == 2,
		"both steps complete in order: " + r.summary())
	_expect(step_titles.size() == 2 and step_titles[0] == "Reach the first marker",
		"step_changed reports each step as it starts: %s" % [step_titles])
	_expect(r.faults.size() == 1 and r.has_fault(&"speeding_serious"),
		"a check limited to step two faults only in step two: " + r.summary())

	r = await _drive([
		{to = Vector3(0, 0, -20), speed = 8.0}, {to = Vector3(0, 0, -45), speed = 2.0}],
		STEPS_FIXTURE)
	_expect(r.reason == &"completed" and r.passed and r.faults.is_empty(),
		"speeding only before its step is not a fault: " + r.summary())

	var dict := r.to_dict()
	_expect(dict.reason == "completed" and dict.passed and dict.steps_completed == 2
		and dict.faults is Array, "to_dict carries the outcome as plain data")

	var runner: ExamRunner = RUNNER.instantiate()
	runner.print_results = false
	root.add_child(runner)
	await process_frame
	_expect(runner.session.is_running(), "an autostarting runner's session is running after one frame")
	var lane: FaultDef = load(FAULTS % "lane_drift")
	var a := Node.new()
	var b := Node.new()
	runner.session.report_fault(lane, Vector3.ZERO, a)
	runner.session.report_fault(lane, Vector3.ZERO, a)
	runner.session.report_fault(lane, Vector3.ZERO, b)
	_expect(runner.session.faults.size() == 2,
		"a repeat from the same check within the window is dropped, another check's is kept")
	a.free()
	b.free()
	runner.queue_free()
	await process_frame
