extends TestCase
## The player's car driving on the vehicle core ([CarDynamics] on its rigid body), and the damped
## spring ([Damped]): it starts in park, pulls away in drive through the gears, settles on its
## springs, brakes with the nose dipping and never reverses on the brake, reverses in R, turns along
## its wheels with less lock at speed, and swings round on the handbrake; and a driver on the keys,
## the accelerator easing as a foot does, cruises in top gear and kicks down only when holding the
## key.

const CAR := preload("res://scenarios/scenes/debug_car.tscn")


func run() -> void:
	_test_spring()
	await _test_drive()
	await _test_reverse_and_handbrake()
	await _test_manual()
	await _test_surfaces()
	await _test_falling()
	await _test_keys_cruise()


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
	var floor := ground()
	var car: Node3D = CAR.instantiate()
	root.add_child(car)
	await physics_frame
	var model: PlayerCarModel = car.model
	var interior: Node3D = model.body.get_node("kiri86_Interior") if model else null
	var hood: Node3D = model.body.get_node("kiri86_Hood") if model else null
	var interior_rest := interior.transform if interior else Transform3D()
	var hood_rest := hood.transform if hood else Transform3D()
	car.held_controls = {throttle = 1.0, select = "D"}
	var gears := {}
	for i in 360:
		await physics_frame
		gears[car.gear] = true
	expect(gears.size() >= 2 and car.gear >= 2,
		"full throttle changes up through the gears: %s, now %d" % [gears.keys(), car.gear])
	expect(car.rpm > car.spec.idle_rpm and car.rpm <= car.spec.redline_rpm,
		"the engine turns: %.0f rpm" % car.rpm)
	expect(car.current_speed > 15.0, "the car pulls away: %.1f m/s after 6 s" % car.current_speed)
	expect(absf(car.global_position.y) < 0.08, "riding on its springs, about on the road: %.3f m"
		% car.global_position.y)
	car.held_controls = {brake = 1.0, select = "D"}
	for i in 20:
		await physics_frame
	if model:
		expect(model.lean_angles.x < -0.01, "braking dips the nose: %.3f" % model.lean_angles.x)
		expect(not hood.transform.is_equal_approx(hood_rest), "the bodywork leans")
		var apart := interior.transform.affine_inverse() * hood.transform
		expect(apart.is_equal_approx(interior_rest.affine_inverse() * hood_rest),
			"and the cockpit with it, as one")
		var cluster: Node3D = car.instruments
		var to_cluster := (model.body.global_transform * interior.transform).affine_inverse() \
			* cluster.global_transform
		expect(cluster.get_parent() == model.cabin and not model.cabin.transform.is_equal_approx(
			Transform3D.IDENTITY), "the instruments lean with it: %s" % to_cluster.origin)
	car.held_controls = {throttle = 0.5, steer = 1.0, select = "D"}
	var facing: Vector3 = -car.global_basis.z
	for i in 60:
		await physics_frame
	var turned := facing.signed_angle_to(-car.global_basis.z, Vector3.UP)
	expect(turned > 0.05, "steering left turns the car left: %.2f rad" % turned)
	expect(car.wheel_angle > 0.0 and car.wheel_angle <= car.spec.steer_lock,
		"the front wheels turn within the lock: %.2f" % car.wheel_angle)
	car.queue_free()
	floor.queue_free()
	await process_frame


func _test_reverse_and_handbrake() -> void:
	var floor := ground()
	var car: Node3D = CAR.instantiate()
	car.assist_preset = "sim"
	root.add_child(car)
	await physics_frame
	expect(car.dynamics.gearbox.letter() == "P", "the car starts in park")
	car.held_controls = {throttle = 1.0}
	await frames(60)
	expect(absf(car.current_speed) < 0.05, "and does not move on the throttle in park: %.2f m/s"
		% car.current_speed)
	car.held_controls = {brake = 1.0, select = "D"}
	await frames(120)
	expect(absf(car.current_speed) < 0.05 and car.gear >= 0,
		"in drive, holding the brake only holds the car, never reversing: %.2f m/s, gear %d"
		% [car.current_speed, car.gear])
	car.held_controls = {throttle = 0.6, select = "R"}
	await frames(120)
	expect(car.current_speed < -0.5 and car.gear == -1,
		"in reverse the throttle drives the car backward: %.1f m/s" % car.current_speed)
	car.held_controls = {brake = 1.0, select = "R"}
	await frames(90)
	expect(absf(car.current_speed) < 0.05, "and the brake stops it: %.2f m/s" % car.current_speed)
	car.held_controls = {throttle = 1.0, select = "D"}
	await frames(240)
	car.held_controls = {throttle = 0.2, steer = 0.3, select = "D"}
	await frames(20)
	var facing: Vector3 = -car.global_basis.z
	car.held_controls = {steer = 0.6, handbrake = 1.0, select = "D"}
	await frames(60)
	var turned := absf(facing.signed_angle_to(-car.global_basis.z, Vector3.UP))
	expect(car.dynamics.spin[CarDynamics.RL] == 0.0 or car.current_speed < 1.0,
		"the handbrake locks the rear wheels")
	expect(turned > deg_to_rad(45.0), "and swings the car round: %.0f°" % rad_to_deg(turned))
	car.queue_free()
	floor.queue_free()
	await process_frame


func _test_manual() -> void:
	var floor := ground()
	var car: Node3D = CAR.instantiate()
	root.add_child(car)
	await physics_frame
	car.dynamics.manual = true
	var up := InputEventAction.new()
	up.action = DriverInput.SHIFT_UP
	up.pressed = true
	Input.parse_input_event(up)
	await frames(2)
	car.held_controls = {throttle = 1.0}
	await frames(240)
	var first: int = car.gear
	Input.parse_input_event(up)
	await frames(30)
	expect(first == 1 and car.gear == 2,
		"in the manual the car holds its gear until the driver changes up: %d, then %d"
		% [first, car.gear])
	expect(car.rpm <= car.spec.redline_rpm, "the limiter holds the revolutions")
	car.queue_free()
	floor.queue_free()
	await process_frame


func _test_surfaces() -> void:
	var speeds := {}
	for type: StringName in [&"asphalt", &"ground"]:
		var floor := ground(400.0, type)
		var car: Node3D = CAR.instantiate()
		car.assist_preset = "sim"
		root.add_child(car)
		await physics_frame
		car.held_controls = {throttle = 1.0, select = "D"}
		await frames(120)
		speeds[type] = car.current_speed
		car.queue_free()
		floor.queue_free()
		await process_frame
	expect(speeds[&"asphalt"] > speeds[&"ground"] + 1.0,
		"the car pulls away harder on asphalt than on grass: %.1f against %.1f m/s"
		% [speeds[&"asphalt"], speeds[&"ground"]])


func _test_falling() -> void:
	var floor := ground()
	var car: Node3D = CAR.instantiate()
	root.add_child(car)
	await physics_frame
	car.held_controls = {throttle = 1.0, select = "D"}
	await frames(120)
	# Lifted 3 m off the road at speed, the throttle shut: it falls with its wheels in the air.
	car.global_position += Vector3.UP * 3.0
	car.reset_physics_interpolation()
	car.held_controls = {select = "D"}
	var revs := []
	for i in 40:
		await physics_frame
		if car.grounded.count(1) == 0:
			revs.append(car.rpm)
	var flared := 0
	for k in range(1, revs.size()):
		if revs[k] > revs[k - 1] + 300.0:
			flared += 1
	expect(revs.size() > 30 and revs[-1] < revs[0] * 0.7 and flared == 0,
		"falling with the throttle shut, the revs fall steadily and never flare: %.0f to %.0f rpm"
		% [revs[0] if revs else 0.0, revs[-1] if revs else 0.0])
	car.queue_free()
	floor.queue_free()
	await process_frame


## A keyboard driver holding 90 km/h: the key down below it, up above it, every step. The
## accelerator eases toward the key, so the automatic settles in top gear and never kicks down;
## holding the key down then kicks it down to overtake.
func _test_keys_cruise() -> void:
	var floor := ground(6000.0)
	var car: Node3D = CAR.instantiate()
	root.add_child(car)
	await physics_frame
	var dyn: CarDynamics = car.dynamics
	var top := Powertrain.gear_count(dyn.spec)
	var target := 25.0
	var kicks := 0
	var last := 0
	for k in 45 * 60:
		car.held_controls = {throttle = 1.0 if car.current_speed < target else 0.0, select = "D"}
		await physics_frame
		if k > 20 * 60 and dyn.gear < last:
			kicks += 1
		last = dyn.gear
	expect(dyn.gear == top and kicks == 0,
		"cruising on the keys at 90 km/h settles in top gear: gear %d, %d kick-downs after 20 s"
		% [dyn.gear, kicks])
	expect(car.throttle < 1.0, "the accelerator never reaches the floor on taps: %.2f"
		% car.throttle)
	car.held_controls = {throttle = 1.0, select = "D"}
	for k in 90:
		await physics_frame
	expect(dyn.gear < top, "holding the key kicks down to overtake: gear %d" % dyn.gear)
	car.queue_free()
	floor.queue_free()
	await process_frame
