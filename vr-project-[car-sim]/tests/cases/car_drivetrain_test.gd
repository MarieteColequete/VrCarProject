extends TestCase
## The player's car's drivetrain and steering ([CarDrivetrain]), the damped spring ([Damped]),
## and the car driving with them: it changes up through the gears, turns along its wheels with
## less lock at speed, and leans its body but not its cockpit.

const CAR := preload("res://scenarios/scenes/debug_car.tscn")
const WHEELBASE := 2.6


func run() -> void:
	_test_rpm()
	_test_gears()
	_test_steering()
	_test_spring()
	await _test_drive()


func _test_rpm() -> void:
	expect(is_equal_approx(CarDrivetrain.rpm(0.0, 1), CarDrivetrain.IDLE_RPM),
		"standing still, the engine idles")
	var first := CarDrivetrain.rpm(10.0, 1)
	var fifth := CarDrivetrain.rpm(10.0, 5)
	expect(first > fifth * 4.0, "a low gear turns the engine faster: %.0f, %.0f" % [first, fifth])
	expect(CarDrivetrain.rpm(100.0, 1) <= CarDrivetrain.REDLINE_RPM, "never past the redline")
	expect(is_equal_approx(CarDrivetrain.rpm(0.0, 0), CarDrivetrain.IDLE_RPM), "neutral idles")


func _test_gears() -> void:
	expect(CarDrivetrain.next_gear(0, 0.0, 0.0) == 1, "from a stop, first")
	expect(CarDrivetrain.next_gear(2, -1.0, 0.0) == -1, "moving back, reverse")
	# Climbing through the gears with a light and a full throttle.
	for throttle in [0.3, 1.0]:
		var gear := 1
		var changes := []
		for step in 260:
			var speed := step * 0.1
			var next := CarDrivetrain.next_gear(gear, speed, throttle)
			if next != gear:
				changes.append(speed)
				gear = next
		# At full throttle the top speed comes in fourth, as in a real car pushed hard.
		var top := 5 if throttle < 0.5 else 4
		expect(gear >= top and changes.size() >= top - 1,
			"throttle %.1f changes up through the gears: %s" % [throttle, changes])
	var gentle_up := _first_change(0.2)
	var hard_up := _first_change(1.0)
	expect(hard_up > gentle_up, "full throttle holds a gear longer: %.1f > %.1f m/s"
		% [hard_up, gentle_up])
	expect(CarDrivetrain.next_gear(4, 3.0, 0.0) == 3, "slowing, it changes down")
	expect(CarDrivetrain.gear_letter(3, 0.0, true) == "P"
		and CarDrivetrain.gear_letter(-1, -1.0, false) == "R"
		and CarDrivetrain.gear_letter(1, 0.0, false) == "N"
		and CarDrivetrain.gear_letter(3, 8.0, false) == "3", "the cluster's gear letters")


func _first_change(throttle: float) -> float:
	for step in 300:
		var speed := step * 0.05
		if CarDrivetrain.next_gear(1, speed, throttle) != 1:
			return speed
	return INF


func _test_steering() -> void:
	expect(is_equal_approx(CarDrivetrain.lock_at(2.0, WHEELBASE), CarDrivetrain.LOCK),
		"at walking pace, full lock")
	var fast := CarDrivetrain.lock_at(25.0, WHEELBASE)
	expect(fast < CarDrivetrain.LOCK * 0.2, "at 90 km/h, little lock: %.1f°" % rad_to_deg(fast))
	for speed in [5.0, 12.0, 25.0]:
		var yaw := CarDrivetrain.yaw_rate(speed, CarDrivetrain.lock_at(speed, WHEELBASE), WHEELBASE)
		expect(speed * yaw <= CarDrivetrain.GRIP + 0.01,
			"a full turn at %.0f m/s stays within the grip: %.1f m/s²" % [speed, speed * yaw])
	expect(CarDrivetrain.yaw_rate(-2.0, 0.3, WHEELBASE) < 0.0, "reversing turns the other way")
	expect(is_zero_approx(CarDrivetrain.yaw_rate(0.0, 0.3, WHEELBASE)),
		"standing still, it does not turn")
	var steer := 0.0
	steer = CarDrivetrain.ease_steer(steer, 1.0, 1.0 / 60.0)
	expect(steer > 0.0 and steer < 0.1, "the steering eases toward the input: %.3f" % steer)
	for i in 60:
		steer = CarDrivetrain.ease_steer(steer, 1.0, 1.0 / 60.0)
	expect(is_equal_approx(steer, 1.0), "and reaches it")
	for i in 30:
		steer = CarDrivetrain.ease_steer(steer, 0.0, 1.0 / 60.0)
	expect(is_zero_approx(steer), "let go, it returns to centre")


func _test_spring() -> void:
	var state := Vector2(0.0, 0.0)
	var highest := 0.0
	for i in 120:
		state = Damped.step(state.x, state.y, 1.0, 10.0, 1.0 / 60.0)
		highest = maxf(highest, state.x)
	expect(absf(state.x - 1.0) < 0.001, "the spring reaches its target: %.4f" % state.x)
	expect(highest <= 1.0 + 0.00001, "without overshooting: %.5f" % highest)
	var long := Damped.step(0.0, 0.0, 1.0, 10.0, 5.0)
	expect(absf(long.x - 1.0) < 0.001, "a long step stays stable")


func _test_drive() -> void:
	var car: Node3D = CAR.instantiate()
	root.add_child(car)
	await physics_frame
	var model: PlayerCarModel = car.model
	var interior: Node3D = model.body.get_node("kiri86_Interior") if model else null
	var hood: Node3D = model.body.get_node("kiri86_Hood") if model else null
	var interior_rest := interior.transform if interior else Transform3D()
	var hood_rest := hood.transform if hood else Transform3D()
	car.held_controls = {throttle = 1.0}
	var gears := {}
	for i in 360:
		await physics_frame
		gears[car.gear] = true
	expect(gears.size() >= 3 and car.gear >= 3,
		"full throttle changes up through the gears: %s, now %d" % [gears.keys(), car.gear])
	expect(car.rpm > CarDrivetrain.IDLE_RPM and car.rpm < CarDrivetrain.REDLINE_RPM,
		"the engine turns: %.0f rpm" % car.rpm)
	car.held_controls = {brake = 1.0}
	for i in 10:
		await physics_frame
	if model:
		expect(model.lean_angles.x < -0.01, "braking dips the nose: %.3f" % model.lean_angles.x)
		expect(not hood.transform.is_equal_approx(hood_rest), "the bodywork leans")
		expect(interior.transform.is_equal_approx(interior_rest), "the cockpit does not")
	car.held_controls = {throttle = 0.5, steer = 1.0}
	var facing: Vector3 = -car.global_basis.z
	for i in 60:
		await physics_frame
	var turned := facing.signed_angle_to(-car.global_basis.z, Vector3.UP)
	expect(turned > 0.05, "steering left turns the car left: %.2f rad" % turned)
	expect(car.wheel_angle > 0.0 and car.wheel_angle <= CarDrivetrain.LOCK,
		"the front wheels turn within the lock: %.2f" % car.wheel_angle)
	car.queue_free()
	await process_frame
