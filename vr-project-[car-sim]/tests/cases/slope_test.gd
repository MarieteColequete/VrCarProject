extends TestCase
## The player's car on ground that is not flat: a 10% ramp it parks on, rolls down and climbs,
## its body pitched with the slope; a crest onto a flat top it settles over; and a hard knock that
## rolls it over, since the body is free.

const CAR := preload("res://scenarios/scenes/debug_car.tscn")
## The ramp's slope: a 10% grade.
const GRADE := 0.1
## How far up the ramp, along it, its top edge is.
const RAMP_HALF := 30.0


func run() -> void:
	await _test_parked()
	await _test_rolling()
	await _test_climbing()
	await _test_crest()
	await _test_roll_over()


func _test_parked() -> void:
	var ramp := _ramp(false)
	var car := _car_on(ramp)
	car.held_controls = {select = "P"}
	await frames(90)
	expect(car.grounded.count(1) == 4, "parked on a 10%% slope, all four wheels touch: %d"
		% car.grounded.count(1))
	var tilt := rad_to_deg(car.global_basis.y.angle_to(ramp.global_basis.y))
	expect(tilt < 1.0, "and the body pitches with the slope: %.2f° off it" % tilt)
	var from: Vector3 = car.global_position
	await frames(180)
	var drift := car.global_position.distance_to(from)
	expect(drift < 0.02, "in P it stays put: %.3f m in 3 s" % drift)
	await _free(car, ramp)


func _test_rolling() -> void:
	var ramp := _ramp(false)
	var car := _car_on(ramp)
	car.held_controls = {select = "P"}
	await frames(60)
	car.held_controls = {select = "N"}
	await frames(2)
	var start := _downhill_speed(car, ramp)
	await frames(120)
	var accel := (_downhill_speed(car, ramp) - start) / 2.0
	expect(accel > 0.6 and accel < 1.0,
		"in N with the brakes off it rolls down at about g·sin, less its losses: %.2f m/s²"
		% accel)
	await _free(car, ramp)


func _test_climbing() -> void:
	var ramp := _ramp(false)
	var car := _car_on(ramp)
	car.held_controls = {select = "D"}
	await frames(30)
	var from: Vector3 = car.global_position
	car.held_controls = {select = "D", throttle = 0.6}
	await frames(240)
	var climbed := (car.global_position - from).dot(-ramp.global_basis.z)
	expect(climbed > 5.0, "in D it pulls away up the slope: %.1f m in 4 s" % climbed)
	await _free(car, ramp)


func _test_crest() -> void:
	var ramp := _ramp(true)
	var car := _car_on(ramp)
	car.held_controls = {select = "D", throttle = 0.7}
	var top := -RAMP_HALF * cos(atan(GRADE)) - 8.0
	for i in 900:
		await physics_frame
		if car.global_position.z < top:
			break
	expect(car.global_position.z < top, "it climbs over the crest: z %.1f" % car.global_position.z)
	car.held_controls = {select = "D", brake = 1.0}
	await frames(150)
	var tilt := rad_to_deg(car.global_basis.y.angle_to(Vector3.UP))
	expect(car.grounded.count(1) == 4 and tilt < 2.0,
		"on the flat top it settles level on four wheels: %.2f°" % tilt)
	await _free(car, ramp)


func _test_roll_over() -> void:
	var floor := ground()
	var car: RigidBody3D = CAR.instantiate()
	root.add_child(car)
	car.held_controls = {select = "P"}
	await frames(30)
	car.apply_impulse(Vector3.UP * 4000.0, Vector3.ZERO)
	car.apply_torque_impulse(-car.global_basis.z * 4500.0)
	var lowest := 1.0
	for i in 240:
		await physics_frame
		lowest = minf(lowest, car.global_basis.y.dot(Vector3.UP))
	expect(lowest < 0.0, "knocked hard sideways, the free body rolls over: up·up %.2f" % lowest)
	await _free(car, floor)


## A 10% ramp climbing toward -Z with its surface through the origin, [constant RAMP_HALF] metres
## each way along it; with [param top], a flat top beyond its upper edge.
func _ramp(top: bool) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Ramp"
	BodyType.of(&"asphalt").apply(body)
	body.transform = Transform3D(Basis(Vector3.RIGHT, atan(GRADE)), Vector3.ZERO)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(30.0, 0.4, RAMP_HALF * 2.0)
	shape.shape = box
	shape.position.y = -0.2
	body.add_child(shape)
	root.add_child(body)
	if top:
		var edge := body.transform * Vector3(0.0, 0.0, -RAMP_HALF)
		var flat := CollisionShape3D.new()
		var slab := BoxShape3D.new()
		slab.size = Vector3(30.0, 0.4, 60.0)
		flat.shape = slab
		# In the ramp's frame: the slab's top meets the ramp's edge and stays level.
		flat.transform = body.transform.affine_inverse() \
			* Transform3D(Basis.IDENTITY, edge + Vector3(0.0, -0.2, -30.0))
		body.add_child(flat)
	return body


## The player's car placed on [param ramp] at its middle, facing up it.
func _car_on(ramp: StaticBody3D) -> RigidBody3D:
	var car: RigidBody3D = CAR.instantiate()
	car.transform = Transform3D(ramp.global_basis, Vector3.ZERO)
	root.add_child(car)
	car.reset_physics_interpolation()
	return car


func _downhill_speed(car: RigidBody3D, ramp: StaticBody3D) -> float:
	return car.linear_velocity.dot(ramp.global_basis.z)


func _free(car: Node, floor: Node) -> void:
	car.queue_free()
	floor.queue_free()
	await physics_frame
