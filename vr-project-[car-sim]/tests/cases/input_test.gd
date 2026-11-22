extends TestCase
## Controls and camera: bindings, the input helpers, the driver view, and the debug car.


func run() -> void:
	_test_bindings()
	_test_driver_input()
	await _test_driver_view()
	await _test_debug_car_controls()


func _has_event(action: StringName, type: String) -> bool:
	for event in InputMap.action_get_events(action):
		if event.is_class(type):
			return true
	return false


func _test_bindings() -> void:
	for action in DriverInput.CAR_ACTIONS + [&"look_reset", &"toggle_view", MirrorAdjust.ACTION]:
		expect(InputMap.has_action(action) and _has_event(action, "InputEventKey")
			and (_has_event(action, "InputEventJoypadMotion")
				or _has_event(action, "InputEventJoypadButton")),
			"%s is bound on the keyboard and the gamepad" % action)
	for action in [&"look_left", &"look_right", &"look_up", &"look_down"]:
		expect(InputMap.has_action(action) and _has_event(action, "InputEventJoypadMotion"),
			"%s is bound to a gamepad stick" % action)
	expect(InputMap.has_action(&"release_mouse") and _has_event(&"release_mouse", "InputEventKey"),
		"release_mouse is bound on the keyboard")


func _release_all() -> void:
	for action in DriverInput.CAR_ACTIONS:
		Input.action_release(action)


func _test_driver_input() -> void:
	Input.action_press(&"throttle", 0.5)
	expect(is_equal_approx(DriverInput.throttle(), 0.5), "half trigger is half throttle")
	Input.action_press(&"brake")
	expect(is_equal_approx(DriverInput.brake(), 1.0), "a brake key is full brake")
	Input.action_press(&"steer_left")
	expect(is_equal_approx(DriverInput.steer(), 1.0), "steer_left alone is full left")
	Input.action_press(&"steer_right")
	expect(is_zero_approx(DriverInput.steer()), "both steer actions cancel out")
	Input.action_release(&"steer_left")
	expect(is_equal_approx(DriverInput.steer(), -1.0), "steer_right alone is full right")
	_release_all()
	expect(is_zero_approx(DriverInput.throttle() + DriverInput.brake() + DriverInput.steer()),
		"released controls are neutral")

	var q := InputEventKey.new()
	q.physical_keycode = KEY_Q
	q.pressed = true
	expect(DriverInput.indicator_pressed(q) == VehicleProbe.Indicator.LEFT, "Q is the left indicator")
	var rb := InputEventJoypadButton.new()
	rb.button_index = JOY_BUTTON_RIGHT_SHOULDER
	rb.pressed = true
	expect(DriverInput.indicator_pressed(rb) == VehicleProbe.Indicator.RIGHT,
		"RB is the right indicator")


func _test_driver_view() -> void:
	var view: DriverView = load("res://player/driver_view.tscn").instantiate()
	view.capture_mouse = false
	view.require_capture = false
	root.add_child(view)
	await process_frame
	expect(not view.vr and view.flat_camera.current, "without a headset the flat camera is current")

	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(-100.0, 40.0)
	view._unhandled_input(motion)
	expect(is_equal_approx(view.yaw, 100.0 * view.mouse_sensitivity)
		and is_equal_approx(view.pitch, -40.0 * view.mouse_sensitivity),
		"mouse motion turns the view by its sensitivity")
	expect(view.look_direction().x < 0.0, "moving the mouse left looks left")

	motion.relative = Vector2(-100000.0, -100000.0)
	view._unhandled_input(motion)
	expect(is_equal_approx(view.yaw, deg_to_rad(view.max_yaw_degrees))
		and is_equal_approx(view.pitch, deg_to_rad(view.max_pitch_degrees)),
		"the view stops at its yaw and pitch limits")

	Input.action_press(&"look_right")
	await process_frame
	await process_frame
	Input.action_release(&"look_right")
	expect(view.yaw < deg_to_rad(view.max_yaw_degrees), "the right stick turns the view")

	view.reset_look()
	expect(is_zero_approx(view.yaw) and is_zero_approx(view.pitch), "look_reset recentres")
	view.queue_free()
	await process_frame


func _test_debug_car_controls() -> void:
	var runner := spawn_runner()
	var car: Node3D = runner.car
	await physics_frame
	var start := car.global_position
	expect(car.dynamics.gearbox.letter() == "P", "the car starts in park")
	for i in 30:
		if runner.session.is_running():
			break
		await physics_frame
	await physics_frame
	expect(car.key_live, "and is once the attempt runs")
	Input.action_press(DriverInput.IGNITION)
	await physics_frame
	await physics_frame
	Input.action_release(DriverInput.IGNITION)
	await physics_frame
	expect(car.dynamics.engine == CarDynamics.EngineState.OFF, "a press of the key switches it off")
	Input.action_press(DriverInput.IGNITION)
	for i in roundi(car.spec.crank_time / DT) + 10:
		await physics_frame
	Input.action_release(DriverInput.IGNITION)
	expect(car.dynamics.engine == CarDynamics.EngineState.RUNNING,
		"and the key held turns it over until it runs again")
	for i in 3:
		_tap(DriverInput.SHIFT_UP)
		await physics_frame
		await physics_frame
	expect(car.dynamics.gearbox.selector == Gearbox.Selector.DRIVE,
		"shift_up three times moves the lever from P through R and N to D")
	Input.action_press(&"throttle")
	for i in 60:
		await physics_frame
	Input.action_press(&"steer_left")
	for i in 30:
		await physics_frame
	_release_all()
	var moved := car.global_position - start
	expect(car.current_speed > 0.0 and moved.z < -1.0, "throttle drives the car forward")
	expect(moved.x < 0.0, "steer_left turns the car left")

	Input.action_press(&"brake")
	for i in 240:
		await physics_frame
	_release_all()
	expect(absf(car.current_speed) < 0.05, "holding the brake stops the car, and never reverses")
	for i in 2:
		_tap(DriverInput.SHIFT_DOWN)
		await physics_frame
		await physics_frame
	Input.action_press(&"throttle")
	for i in 90:
		await physics_frame
	_release_all()
	expect(car.current_speed < 0.0, "in R, the throttle reverses")

	var probe := VehicleProbe.of(car)
	Input.action_press(&"handbrake")
	await physics_frame
	await physics_frame
	expect(probe.handbrake == VehicleProbe.Toggle.ON, "the handbrake reaches the probe")
	Input.action_release(&"handbrake")
	await physics_frame
	await physics_frame
	expect(probe.handbrake == VehicleProbe.Toggle.OFF, "releasing the handbrake reaches the probe")

	car._unhandled_input(_action_event(&"toggle_view"))
	expect(car.chase_camera.current and not car.driver_view.active, "toggle_view shows the chase camera")
	runner.queue_free()
	await process_frame


func _action_event(action: StringName) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	return event


func _tap(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)
	event = InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)
