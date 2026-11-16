extends SceneTree
## Headless tests of the scenario system. Run from the repository root:
##   godot --headless --fixed-fps 60 --path 'vr-project-[car-sim]' -s res://tests/run_tests.gd
## Exits 0 when every test passes, 1 otherwise; TESTS_VERBOSE=1 also prints each pass. Drives
## move the car along fixed legs, one step per physics tick, so results do not depend on the
## machine's speed. --fixed-fps 60 makes each frame one tick without waiting for the clock, so
## minutes of simulated driving run in seconds.

const RUNNER := preload("res://scenarios/scenes/exam_runner.tscn")
const POLICY := preload("res://scenarios/data/default_policy.tres")
const FAULTS := "res://scenarios/data/faults/%s.tres"
const STEPS_FIXTURE := preload("res://tests/fixtures/steps_fixture.tscn")
const LINES_FIXTURE := preload("res://tests/fixtures/lines_fixture.tscn")
const BAY_PARKING := preload("res://scenarios/scenes/bay_parking/bay_parking.tscn")
const PARALLEL_PARKING := preload("res://scenarios/scenes/parallel_parking/parallel_parking.tscn")
const TRAFFIC_FIXTURE := preload("res://tests/fixtures/traffic_fixture.tscn")

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
	await _test_markings()
	await _test_lines()
	await _test_bay_parking()
	await _test_parallel_parking()
	await _test_scripted_agent()
	await _test_traffic_light()
	await _test_spawner()
	await _test_traffic_drives()
	print("\n%d passed, %d failed" % [_passed, _failed])
	quit(1 if _failed > 0 else 0)


func _expect(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		if OS.has_environment("TESTS_VERBOSE"):
			print("ok: ", what)
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
## facing away from it with reverse = true, or keeping its heading with crab = true; {wait: s}
## stays put; {turn: degrees} turns in place (positive is left); {indicator: Indicator} sets the
## probe's indicator. [param on_spawn] is called
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
		if leg.has("indicator"):
			VehicleProbe.of(car).indicator = leg.indicator
			continue
		if leg.has("turn"):
			car.rotate_y(deg_to_rad(leg.turn))
			await physics_frame
			continue
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
			if dir.length() > 0.01 and not leg.get("crab", false):
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


# --- Road markings and lines -----------------------------------------------------------------------

func _marking(kind: RoadMarking.Kind, from: Vector3, to: Vector3) -> RoadMarking:
	var marking := RoadMarking.new()
	marking.kind = kind
	marking.curve = Curve3D.new()
	marking.curve.add_point(from)
	marking.curve.add_point(to)
	root.add_child(marking)
	return marking


func _vertex_count(marking: RoadMarking) -> int:
	var mesh := marking.get_child(0, true) as MeshInstance3D
	if mesh == null or mesh.mesh == null:
		return 0
	return mesh.mesh.surface_get_array_len(0)


func _test_markings() -> void:
	var solid := _marking(RoadMarking.Kind.SOLID, Vector3(0, 0, 0), Vector3(0, 0, -30))
	var dashed := _marking(RoadMarking.Kind.DASHED, Vector3(5, 0, 0), Vector3(5, 0, -30))
	await process_frame
	_expect(_vertex_count(solid) > 0, "a solid line draws paint")
	_expect(_vertex_count(dashed) > 0 and _vertex_count(dashed) < _vertex_count(solid) / 2,
		"a dashed line draws a third of a solid one (3 m dash, 6 m gap)")

	var index := MarkingIndex.new()
	index.add(solid)
	index.add(dashed)
	var hits := index.crossings(Vector3(-1, 0, -10), Vector3(1, 0, -10))
	_expect(hits.size() == 1 and hits[0].marking == solid
		and (hits[0].normal as Vector3).is_equal_approx(Vector3.RIGHT),
		"a point moving right across the solid line crosses it once, onto its right")
	_expect(index.crossings(Vector3(-1, 0, -10), Vector3(-0.5, 0, -10)).is_empty(),
		"a point short of the line does not cross it")
	_expect(index.crossings(Vector3(4, 0, -12), Vector3(6, 0, -12)).size() == 1,
		"a dashed line is crossed in its gaps too")
	_expect(index.overlapping(Vector3(0.05, 0, -20)) == [solid]
		and index.overlapping(Vector3(0.3, 0, -20)).is_empty(),
		"a point within the paint is on the line, one beside it is not")
	solid.free()
	dashed.free()


func _test_lines() -> void:
	var left := VehicleProbe.Indicator.LEFT
	var off := VehicleProbe.Indicator.OFF
	var r := await _drive([{to = Vector3(1.75, 0, -100), speed = 8.0}], LINES_FIXTURE)
	_expect(r.reason == &"completed" and r.faults.is_empty(), "keeping to the lane is clean: " + r.summary())

	r = await _drive([
		{indicator = left}, {to = Vector3(1.75, 0, -10), speed = 8.0},
		{to = Vector3(-1.75, 0, -25), speed = 8.0}, {indicator = off},
		{to = Vector3(-1.75, 0, -100), speed = 8.0}], LINES_FIXTURE)
	_expect(r.reason == &"completed" and r.faults.is_empty(),
		"crossing the dashed line while indicating left is clean: " + r.summary())

	r = await _drive([
		{to = Vector3(1.75, 0, -10), speed = 8.0}, {to = Vector3(-1.75, 0, -25), speed = 8.0},
		{to = Vector3(-1.75, 0, -100), speed = 8.0}], LINES_FIXTURE)
	_expect(r.reason == &"completed" and r.faults.size() == 1 and r.has_fault(&"no_indicator"),
		"crossing the dashed line without indicating is one minor fault: " + r.summary())

	r = await _drive([
		{indicator = VehicleProbe.Indicator.RIGHT}, {to = Vector3(1.75, 0, -10), speed = 8.0},
		{to = Vector3(-1.75, 0, -25), speed = 8.0}, {to = Vector3(-1.75, 0, -100), speed = 8.0}],
		LINES_FIXTURE)
	_expect(r.faults.size() == 1 and r.has_fault(&"no_indicator"),
		"indicating the wrong way is no indication: " + r.summary())

	r = await _drive([
		{indicator = left}, {to = Vector3(1.75, 0, -50), speed = 8.0},
		{to = Vector3(-1.75, 0, -65), speed = 8.0}, {to = Vector3(-1.75, 0, -100), speed = 8.0}],
		LINES_FIXTURE)
	_expect(r.faults.size() == 1 and r.has_fault(&"line_solid_crossed"),
		"crossing the solid line is a serious fault even when indicating: " + r.summary())

	r = await _drive([
		{to = Vector3(0.85, 0, -30), speed = 8.0}, {to = Vector3(0.85, 0, -100), speed = 8.0}],
		LINES_FIXTURE)
	_expect(r.reason == &"completed" and r.faults.size() == 1 and r.has_fault(&"line_straddled"),
		"riding on the centre line is one minor fault: " + r.summary())

	r = await _drive([
		{to = Vector3(1.75, 0, -10), speed = 8.0}, {to = Vector3(3.0, 0, -25), speed = 8.0},
		{to = Vector3(3.0, 0, -100), speed = 8.0}], LINES_FIXTURE)
	_expect(r.faults.size() == 1 and r.has_fault(&"kerb_mounted"),
		"crossing the kerb is one serious fault: " + r.summary())


# --- Parking ---------------------------------------------------------------------------------------

## The free bay of the bay parking scenario, entered from the aisle at x = 3.
const FREE_BAY := Vector3(5.5, 0, -7.5)


func _reverse_into(bay: Vector3) -> Array:
	return [{to = Vector3(0, 0, bay.z), speed = 5.0}, {to = bay, speed = 2.0, reverse = true}]


func _test_bay_parking() -> void:
	var scene := BAY_PARKING.instantiate()
	var into: Vector3 = -scene.get_node("Bays/Bay2").transform.basis.z
	_expect(into.is_equal_approx(Vector3.RIGHT), "the car park's bays open onto the aisle")
	scene.free()

	var r := await _drive(_reverse_into(FREE_BAY) + [{wait = 3.0}], BAY_PARKING)
	_expect(r.reason == &"completed" and r.passed and r.faults.is_empty(),
		"reversing straight into a free bay is clean: " + r.summary())

	r = await _drive(_reverse_into(Vector3(4.0, 0, -7.5)) + [{wait = 3.0}], BAY_PARKING)
	_expect(r.reason == &"completed" and r.faults.size() == 1
		and r.has_fault(&"parking_overhang_serious"),
		"stopping half out of the bay is a serious overhang: " + r.summary())

	r = await _drive(_reverse_into(FREE_BAY) + [{turn = 12.0}, {wait = 3.0}], BAY_PARKING)
	_expect(r.reason == &"completed" and r.has_fault(&"parking_misaligned"),
		"ending 12 degrees off is crooked: " + r.summary())

	r = await _drive([
		{to = Vector3(0, 0, -7.5), speed = 5.0}, {to = Vector3(2, 0, -7.5), speed = 2.0, reverse = true},
		{to = Vector3(1, 0, -7.5), speed = 2.0}, {to = Vector3(3, 0, -7.5), speed = 2.0, reverse = true},
		{to = Vector3(2, 0, -7.5), speed = 2.0}, {to = FREE_BAY, speed = 2.0, reverse = true},
		{wait = 3.0}], BAY_PARKING)
	_expect(r.reason == &"completed" and r.faults.size() == 1
		and r.has_fault(&"parking_too_many_manoeuvres"),
		"five direction changes is too many manoeuvres: " + r.summary())

	r = await _drive([{wait = 50.0}] + _reverse_into(FREE_BAY) + [{wait = 3.0}], BAY_PARKING)
	_expect(r.reason == &"completed" and r.faults.size() == 1 and r.has_fault(&"parking_too_slow"),
		"taking longer than the limit is too slow: " + r.summary())

	r = await _drive(_reverse_into(Vector3(5.5, 0, -12.5)) + [{wait = 6.0}], BAY_PARKING)
	_expect(r.reason == &"aborted" and r.faults.size() == 1 and r.has_fault(&"parking_reserved"),
		"the reserved bay is a fault and does not complete the step: " + r.summary())

	r = await _drive([{to = Vector3(0, 0, -26), speed = 5.0}, {wait = 6.0}], BAY_PARKING)
	_expect(r.faults.size() == 1 and r.has_fault(&"parking_illegal"),
		"settling in the fire lane is illegal parking: " + r.summary())

	r = await _drive([{to = Vector3(-2.0, 0, -15), speed = 5.0}, {wait = 6.0}], BAY_PARKING)
	_expect(r.faults.size() == 1 and r.has_fault(&"parking_illegal"),
		"settling on the yellow line is illegal parking: " + r.summary())

	r = await _drive([{to = Vector3(0, 0, -15), speed = 5.0}, {wait = 3.0},
		{to = Vector3(0, 0, -7.5), speed = 2.0, reverse = true},
		{to = FREE_BAY, speed = 2.0, reverse = true}, {wait = 3.0}], BAY_PARKING)
	_expect(r.reason == &"completed" and r.faults.is_empty(),
		"a short stop in the aisle is neither parking nor a fault: " + r.summary())


func _test_parallel_parking() -> void:
	var gap := Vector3(4.65, 0, -21.25)
	var r := await _drive([
		{to = Vector3(1.75, 0, gap.z), speed = 6.0}, {to = gap, speed = 1.0, crab = true},
		{wait = 3.0}], PARALLEL_PARKING)
	_expect(r.reason == &"completed" and r.faults.is_empty(),
		"parking in the gap by the kerb is clean: " + r.summary())

	r = await _drive([
		{to = Vector3(1.75, 0, gap.z), speed = 6.0}, {to = Vector3(3.9, 0, gap.z), speed = 1.0, crab = true},
		{wait = 3.0}], PARALLEL_PARKING)
	_expect(r.reason == &"completed" and r.faults.size() == 1
		and r.has_fault(&"parking_overhang_serious"),
		"stopping with half the car in the road is a serious overhang: " + r.summary())

	r = await _drive([
		{to = Vector3(1.75, 0, -8), speed = 6.0}, {to = Vector3(4.65, 0, -8), speed = 1.0, crab = true},
		{wait = 6.0}], PARALLEL_PARKING)
	_expect(r.faults.size() == 1 and r.has_fault(&"parking_illegal"),
		"parking along the no-parking line is illegal: " + r.summary())


# --- Other road users ------------------------------------------------------------------------------

func _frames(n: int) -> void:
	for i in n:
		await physics_frame


func _straight_path(from: Vector3, to: Vector3) -> Path3D:
	var path := Path3D.new()
	path.curve = Curve3D.new()
	path.curve.add_point(from)
	path.curve.add_point(to)
	root.add_child(path)
	return path


func _test_scripted_agent() -> void:
	var path := _straight_path(Vector3.ZERO, Vector3(0, 0, -20))
	var agent := ScriptedAgent.new()
	agent.path = path
	agent.speed = 5.0
	agent.start_delay = 1.0
	var finished := [false]
	agent.finished.connect(func() -> void: finished[0] = true)
	root.add_child(agent)
	await _frames(30)
	_expect(agent.state == ScriptedAgent.State.WAITING and agent.global_position.is_zero_approx(),
		"an agent waits out its start delay at the start of its path")
	_expect(absf(agent.time_to(20.0) - (0.5 + 4.0)) < 0.05,
		"time_to counts the remaining delay and the distance at speed (%.3f)" % agent.time_to(20.0))
	await _frames(90)
	_expect(agent.state == ScriptedAgent.State.MOVING and absf(agent.progress - 5.0) < 0.2,
		"one second after starting, it is 5 m along at 5 m/s (%.2f)" % agent.progress)
	_expect((-agent.global_basis.z).is_equal_approx(Vector3(0, 0, -1)), "it faces along its path")
	await _frames(240)
	_expect(agent.state == ScriptedAgent.State.DONE and finished[0]
		and agent.global_position.is_equal_approx(Vector3(0, 0, -20)),
		"at the end of its path it stops and reports finished")
	agent.free()

	var pauser := ScriptedAgent.new()
	pauser.path = path
	pauser.speed = 5.0
	pauser.pause_at = 10.0
	pauser.pause_time = 2.0
	root.add_child(pauser)
	_expect(is_equal_approx(pauser.time_to(20.0), 4.0 + 2.0), "time_to includes a pause still ahead")
	await _frames(180)
	_expect(pauser.state == ScriptedAgent.State.PAUSED and is_equal_approx(pauser.progress, 10.0),
		"it pauses at its pause point")
	await _frames(70)
	_expect(pauser.state == ScriptedAgent.State.MOVING, "and moves on after the pause")
	pauser.free()

	var looper := ScriptedAgent.new()
	looper.path = path
	looper.speed = 10.0
	looper.loop = true
	root.add_child(looper)
	await _frames(150)
	_expect(looper.state == ScriptedAgent.State.MOVING and absf(looper.progress - 5.0) < 0.3,
		"a looping agent starts its next lap (%.2f)" % looper.progress)
	_expect(looper.collision_layer == VehicleProbe.OBSTACLE_LAYER and not looper.is_in_group(&"pedestrian"),
		"a car agent is an obstacle")
	looper.free()
	path.free()


func _test_traffic_light() -> void:
	var light := TrafficLight.new()
	light.red_time = 1.0
	light.red_amber_time = 0.5
	light.green_time = 1.0
	light.amber_time = 0.5
	var seen: Array[TrafficLight.Light] = []
	light.state_changed.connect(func(s: TrafficLight.Light) -> void: seen.append(s))
	root.add_child(light)
	_expect(light.state == TrafficLight.Light.RED and light.is_red(), "a cycling light starts at its initial phase")
	await _frames(190)
	_expect(seen == [TrafficLight.Light.RED_AMBER, TrafficLight.Light.GREEN, TrafficLight.Light.AMBER,
		TrafficLight.Light.RED], "it runs red and amber, green, amber, red on its timers: %s" % [seen])
	light.free()

	var approach := TrafficLight.new()
	approach.mode = TrafficLight.Mode.ON_APPROACH
	approach.initial = TrafficLight.Light.GREEN
	approach.trigger_delay = 0.5
	approach.amber_time = 1.0
	approach.red_time = 1.0
	approach.red_amber_time = 0.5
	seen.clear()
	approach.state_changed.connect(func(s: TrafficLight.Light) -> void: seen.append(s))
	root.add_child(approach)
	await _frames(120)
	_expect(seen.is_empty() and approach.state == TrafficLight.Light.GREEN,
		"a light on approach holds green until triggered")
	approach._on_triggered(null)
	await _frames(20)
	_expect(approach.state == TrafficLight.Light.GREEN, "and waits out its trigger delay")
	await _frames(20)
	_expect(approach.state == TrafficLight.Light.AMBER, "then turns amber")
	await _frames(600)
	_expect(seen == [TrafficLight.Light.AMBER, TrafficLight.Light.RED, TrafficLight.Light.RED_AMBER,
		TrafficLight.Light.GREEN], "and runs once round to green, where it holds: %s" % [seen])
	approach.free()


func _bays(count: int) -> Array[ParkingBay]:
	var bays: Array[ParkingBay] = []
	for i in count:
		var bay := ParkingBay.new()
		bay.position = Vector3(i * 3.0, 0, -50)
		root.add_child(bay)
		bays.append(bay)
	return bays


func _filled_indices(seed_value: int, occupancy: float, reserved_index := -1) -> Array[int]:
	var bays := _bays(6)
	if reserved_index >= 0:
		bays[reserved_index].reserved = true
	var spawner := AgentSpawner.new()
	spawner.random_seed = seed_value
	spawner.occupancy = occupancy
	spawner.bays = bays
	root.add_child(spawner)
	var out: Array[int] = []
	for i in bays.size():
		if bays[i].occupied:
			out.append(i)
	spawner.free()
	for bay in bays:
		bay.free()
	return out


func _test_spawner() -> void:
	var first := _filled_indices(7, 0.5)
	_expect(first.size() == 3, "half of six bays are filled (%s)" % [first])
	_expect(_filled_indices(7, 0.5) == first, "the same seed fills the same bays")
	var others := [first]
	for seed_value in [1, 2, 3, 4, 5]:
		others.append(_filled_indices(seed_value, 0.5))
	var distinct := {}
	for set_ in others:
		distinct[str(set_)] = true
	_expect(distinct.size() > 1, "different seeds fill different bays")
	_expect(_filled_indices(3, 1.0).size() == 5, "a full car park still keeps one bay free")
	_expect(not _filled_indices(3, 1.0, 2).has(2), "a reserved bay is never filled")

	var bays := _bays(2)
	var spawner := AgentSpawner.new()
	spawner.occupancy = 0.5
	spawner.keep_free = 0
	spawner.bays = bays
	root.add_child(spawner)
	await physics_frame
	await physics_frame
	var taken := bays[0] if bays[0].occupied else bays[1]
	var other := bays[1] if taken == bays[0] else bays[0]
	taken.occupied = false
	_expect(not taken.is_free() and other.is_free(),
		"a spawned car stands in its bay, so the bay reads as taken even unmarked")
	spawner.free()
	for bay in bays:
		bay.free()


func _test_traffic_drives() -> void:
	var r := await _drive([{to = Vector3(1.75, 0, -62), speed = 8.0}], TRAFFIC_FIXTURE)
	_expect(r.reason == &"completed" and r.faults.is_empty(),
		"passing before the pedestrian reaches the lane is clean: " + r.summary())

	r = await _drive([{to = Vector3(1.75, 0, -20), speed = 4.0}, {wait = 8.0}], TRAFFIC_FIXTURE)
	_expect(r.has_fault(&"contact_pedestrian") and r.reason == &"eliminated",
		"waiting on the pedestrian's path gets the car walked into: " + r.summary())
