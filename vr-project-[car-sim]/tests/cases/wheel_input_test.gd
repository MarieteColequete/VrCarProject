extends TestCase
## A steering wheel and pedals ([WheelInput]): the rim turned 1:1 into the car's own wheel up to its
## lock, pedals calibrated either way round, the settings read from a file, on the car a wheel
## steering at once where keys steer at a hand's pace, and in VR the seat lined up with a real rim.


## A wheel always connected, its rim where the test puts it.
class FakeWheel:
	extends WheelInput
	var rim := 0.0

	func active() -> bool:
		return true

	func steer() -> float:
		return WheelInput.turn(rim, rotation)


func run() -> void:
	_test_turn()
	_test_pedal()
	_test_settings()
	await _test_on_car()
	await _test_align_seat()


func _test_turn() -> void:
	var lock := rad_to_deg(Steering.WHEEL_TURN)
	expect(is_equal_approx(lock, 450.0), "the car's wheel turns 900 degrees lock to lock")
	expect(is_zero_approx(WheelInput.turn(0.0, 900.0)), "a centred rim leaves the car straight")
	expect(is_equal_approx(WheelInput.turn(0.5, 900.0), -0.5)
		and is_equal_approx(WheelInput.turn(-1.0, 900.0), 1.0),
		"a 900 degree wheel matches the car's: halfway right is half lock, full left full lock")
	var degrees := 60.0
	expect(is_equal_approx(WheelInput.turn(degrees / 540.0, 1080.0) * lock, -degrees),
		"on a 1080 degree wheel the car's wheel still turns as far as the rim: 60 degrees")
	expect(is_equal_approx(WheelInput.turn(-1.0, 1080.0), 1.0),
		"and past the car's lock it stays at full lock")


func _test_pedal() -> void:
	expect(is_zero_approx(WheelInput.pedal(-1.0, -1.0, 1.0))
		and is_equal_approx(WheelInput.pedal(0.0, -1.0, 1.0), 0.5)
		and is_equal_approx(WheelInput.pedal(1.0, -1.0, 1.0), 1.0),
		"a pedal resting at -1 and pressed at 1 reads 0, a half, and full")
	expect(is_equal_approx(WheelInput.pedal(-1.0, 1.0, -1.0), 1.0)
		and is_zero_approx(WheelInput.pedal(1.0, 1.0, -1.0)),
		"an inverted pedal, resting at 1, reads the same")
	expect(is_zero_approx(WheelInput.pedal(0.3, 0.0, 0.0)), "an uncalibrated pedal reads nothing")


func _test_settings() -> void:
	var file_path := "user://wheel_input_test.cfg"
	var config := ConfigFile.new()
	config.set_value(WheelInput.SECTION, "enabled", false)
	config.set_value(WheelInput.SECTION, "rotation", 900.0)
	config.set_value(WheelInput.SECTION, "brake_axis", 3)
	config.save(file_path)
	var wheel := WheelInput.load_from(file_path)
	expect(is_equal_approx(wheel.rotation, 900.0) and wheel.brake_axis == 3
		and not wheel.active() and is_zero_approx(wheel.brake()),
		"the settings are read, and a wheel switched off reads nothing")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	var defaults := WheelInput.load_from("user://none_such.cfg")
	expect(is_equal_approx(defaults.rotation, 900.0) and defaults.throttle_axis == -1,
		"without a file the rim is a 900 degree wheel, the car's own")

	var g29 := {"vendor_id": "1133", "product_id": "49812"}
	expect(defaults.pedal_settings("throttle", g29) == Vector3(1, 0, -1)
		and defaults.pedal_settings("brake", g29) == Vector3(1, 0, 1),
		"a G29 in PS3 mode reads both pedals from axis 1 with no file: throttle to -1, brake to 1")
	expect(is_equal_approx(WheelInput.pedal(-1.0, 0.0, -1.0), 1.0)
		and is_zero_approx(WheelInput.pedal(1.0, 0.0, -1.0)),
		"on that combined axis the brake's half does not press the throttle")
	var native := {"vendor_id": "1133", "product_id": "49743"}
	expect(defaults.pedal_settings("throttle", native) == Vector3(1, 1, -1)
		and defaults.pedal_settings("brake", native) == Vector3(2, 1, -1),
		"a G29 in native mode reads the throttle on axis 1 and the brake on axis 2, resting at 1")
	expect(defaults.paddle_of(4, native) == 1 and defaults.paddle_of(5, native) == -1
		and defaults.paddle_of(0, native) == 0,
		"a G29 in native mode shifts up with its right paddle (button 4), down with its left (5)")
	var held := func(buttons: Array) -> Callable:
		return func(button: int) -> bool: return buttons.has(button)
	expect(defaults.shifter_position(held.call([16]), native) == "D"
		and defaults.shifter_position(held.call([15]), native) == "P"
		and defaults.shifter_position(held.call([18]), native) == "R",
		"a G29's shifter in fifth is D, in fourth P, and in reverse R")
	expect(defaults.shifter_position(held.call([]), native) == "N"
		and defaults.shifter_position(held.call([12]), native) == "N",
		"the shifter in neutral, or in a gear with no lever position, is N")
	expect(defaults.shifter_position(held.call([11, 12, 13, 14]), native) == "N",
		"the D-pad, which shares buttons 11 to 14 with first to third gear, moves no lever")
	expect(defaults.shifter_position(held.call([14]), {"vendor_id": "1", "product_id": "2"}) == "",
		"a joypad with no shifter set has no shifter position")
	var shifter := WheelInput.new()
	expect(shifter.shifter_step("N") == "", "a shifter first seen in neutral leaves the lever")
	expect(shifter.shifter_step("D") == "D" and shifter.shifter_step("D") == "",
		"moving the shifter puts the lever there once, not every step")
	expect(shifter.shifter_step("N") == "N" and shifter.shifter_step("P") == "P",
		"back through neutral to park puts the lever in N, then P")
	expect(WheelInput.new().shifter_step("D") == "D",
		"a shifter first seen in a set position puts the lever there at once")
	expect(defaults.paddle_of(4, {"vendor_id": "1", "product_id": "2"}) == 0,
		"a joypad with no profile leaves its paddles to the gamepad's shoulders")
	expect(is_zero_approx(WheelInput.pedal_reading(0.0, 1.0, -1.0, false))
		and is_equal_approx(WheelInput.pedal_reading(0.0, 1.0, -1.0, true), 0.5),
		"a pedal resting at 1 reads released until its axis reports, then half pressed at 0")
	expect(is_equal_approx(WheelInput.pedal_reading(-1.0, 0.0, -1.0, false), 1.0),
		"a pedal resting at 0 needs no report to read")
	expect(defaults.pedal_settings("throttle", {"vendor_id": "1", "product_id": "2"}).x == -1.0,
		"a joypad with no profile leaves its pedals to the input actions")
	config = ConfigFile.new()
	config.set_value(WheelInput.SECTION, "throttle_axis", 2)
	config.save(file_path)
	var overridden := WheelInput.load_from(file_path)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(file_path))
	expect(overridden.pedal_settings("throttle", g29) == Vector3(2, 0, -1),
		"a setting in the file wins over the profile, which still gives the rest")
	var guard: GDScript = load("res://autoload/wheel_guard.gd")
	expect(guard.devices(-1, -1, [0, 1]) == [-1] and guard.devices(1, -1, [0]) == [1],
		"with no wheel an action's joypad axes stay bound as they are")
	expect(guard.devices(-1, 0, [1, 2]) == [1, 2] and guard.devices(-1, 0, []) == [],
		"with a wheel an axis bound for every joypad is bound for each other one, none alone")
	expect(guard.devices(0, 0, [1]) == [] and guard.devices(1, 0, [1]) == [1],
		"an axis bound for the wheel itself goes, one bound for another joypad stays")


func _test_on_car() -> void:
	var before := DriverInput.wheel
	var wheel := FakeWheel.new()
	DriverInput.wheel = wheel
	var car := spawn_car({settings_path = "user://none_such.cfg"})
	await physics_frame
	wheel.rim = 0.25
	await physics_frame
	await physics_frame
	expect(is_equal_approx(car.steering.turn, WheelInput.turn(0.25, wheel.rotation)),
		"a wheel turns the car's at once, with no hand's pace: %.3f" % car.steering.turn)
	DriverInput.wheel = before
	car.queue_free()
	await process_frame


func _test_align_seat() -> void:
	var seat := Transform3D(Basis(Vector3.UP, 0.5), Vector3(2, 1, 3))
	var shift := DriverView.seat_shift(seat, Vector3(2.4, 0.9, 2.5), Vector3(2.3, 1.0, 2.6))
	expect((seat.basis * shift).is_equal_approx(Vector3(0.1, -0.1, -0.1)),
		"the seat shifts, in its own space, by what takes the hands' midpoint onto the car's rim")
	var view: DriverView = load("res://player/driver_view.tscn").instantiate()
	view.capture_mouse = false
	view.controls_path = "user://wheel_align_test.cfg"
	root.add_child(view)
	await process_frame
	view.align_seat(Transform3D(Basis(), view.global_position + Vector3(0, -0.3, -0.5)),
		view.global_position + Vector3(0.1, -0.2, -0.3))
	var config := ConfigFile.new()
	config.load(view.controls_path)
	var kept: Vector3 = config.get_value(DriverView.VR_SECTION, &"seat_offset", Vector3.ZERO)
	expect(view.seat_offset.is_equal_approx(Vector3(-0.1, -0.1, -0.2))
		and kept.is_equal_approx(view.seat_offset)
		and view.xr_origin.position.is_equal_approx(view.seat_offset),
		"aligning moves the headset's room onto the car's rim and keeps it: %s" % view.seat_offset)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(view.controls_path))
	view.queue_free()
	await process_frame
