extends TestCase
## Steering turns the wheels and nothing else: the car moves only by its wheels' torque, its own
## momentum and gravity. Each plant module on its own, fed by hand: the steering ([Steering]) is
## geometry, the tyre's contact ([method TyreModel.contact]) pushes only as its patch slides, and
## the corners ([Suspension]) carry the load. Then the whole car: standing still and steered back
## and forth, in neutral, in park or on the handbrake, it stays put; coasting through a slalom, it
## never gains energy.

const KIRI := preload("res://scenarios/vehicle/specs/kiri86.tres")


func run() -> void:
	_test_steering()
	_test_contact_still()
	_test_contact_rolling()
	_test_contact_energy()
	_test_suspension()
	for held in [{select = "N"}, {select = "P"}, {select = "N", handbrake = 1.0}]:
		await _test_steered_standing(held)
	await _test_coasting_slalom()


func _test_steering() -> void:
	var spec := KIRI.packed()
	var rack := Steering.new()
	rack.steer(spec, 0.5)
	var inner := rack.angles[CarDynamics.FL]
	var outer := rack.angles[CarDynamics.FR]
	expect(inner > outer and outer > 0.0 and rack.angles[CarDynamics.RL] == 0.0,
		"turning left, the inner front turns further than the outer, the rears not at all")
	# Ackermann: both fronts point square to one centre on the rear axle's line.
	var base := KIRI.wheelbase
	var half := KIRI.track * 0.5
	var from_inner := base / tan(inner) + half
	var from_outer := base / tan(outer) - half
	expect(absf(from_inner - from_outer) < 0.001,
		"and both roll round one centre: %.3f m and %.3f m out" % [from_inner, from_outer])
	rack.steer(spec, -1.0)
	expect(is_equal_approx(rack.rack, -KIRI.steer_lock) and rack.angles[CarDynamics.FR] < 0.0,
		"full right is the rack's whole lock to the right")
	rack.steer(spec, 0.0)
	expect(rack.angles == PackedFloat64Array([0.0, 0.0, 0.0, 0.0]), "centred, the wheels are straight")


func _test_contact_still() -> void:
	var spec := KIRI.packed()
	var still := TyreModel.contact(spec, Vector2.ZERO, 0.0, 0.0, 0.0, 3000.0, 1.0, DT)
	expect(still == Vector4.ZERO, "a still patch pushes nothing")
	# A tread already deflected, the wheel (held by its brake, so it cannot roll the tread off)
	# turned under it: it still pushes only back toward where it lay, not along its new side.
	var dyn := CarDynamics.new(spec, Assists.preset("sim"))
	dyn.deflect[CarDynamics.FL] = Vector2(0.0, 0.2)
	var angles := PackedFloat64Array([0.4, 0.4, 0.0, 0.0])
	var loads := PackedFloat64Array([3000.0, 3000.0, 3000.0, 3000.0])
	var none := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	dyn.step(DT, {select = Gearbox.Selector.NEUTRAL, angles = angles, brake = 1.0}, loads, none,
		none,
		PackedFloat64Array([1.0, 1.0, 1.0, 1.0]))
	var f := dyn.force[CarDynamics.FL]
	# The deflection lay across the old heading; the push is back along it, to the wheel's right,
	# turned 0.4 rad from its side, give or take the tread being stiffer along than across.
	var lying := Vector2(f.x, f.y).angle()
	expect(f.length() > 0.0 and absf(absf(lying) - (PI * 0.5 + 0.4)) < 0.15,
		"turned on a deflected tread, the wheel pushes back where the tread lay: %.2f rad" % lying)
	# Held by its brake on a slope's pull, the tread holds as static friction, and creeps nothing.
	var held := Vector2.ZERO
	var crept := 0.0
	var v := 0.0
	for i in 120:
		var touch := TyreModel.contact(spec, held, 0.0, v, 0.0, 3000.0, 1.0, DT)
		held = Vector2(touch.z, touch.w)
		# A quarter of a car on a 10% slope, the tyre pulling it back.
		var pull := 312.0 * CarSpec.G * 0.1 + touch.x
		v += pull / 312.0 * DT
		crept += v * DT
	expect(absf(crept) < 0.01, "held on a slope it creeps %.4f m in 2 s" % crept)


func _test_contact_rolling() -> void:
	var spec := KIRI.packed()
	for slip in [Vector2(0.04, 0.0), Vector2(0.0, 0.05), Vector2(-0.05, 0.08)]:
		var u := Vector2.ZERO
		var touch := Vector4.ZERO
		var along := 20.0
		var across := along * tan(slip.y)
		for i in 120:
			touch = TyreModel.contact(spec, u, along * (1.0 + slip.x), along, across, 3000.0, 1.0,
				DT)
			u = Vector2(touch.z, touch.w)
		var steady := TyreModel.force(spec, slip.x, atan2(across, along), 3000.0, 1.0)
		expect(Vector2(touch.x, touch.y).distance_to(steady) < steady.length() * 0.03,
			"rolling at 20 m/s at slip %s it settles to the tyre's steady force: %s against %s"
			% [slip, Vector2(touch.x, touch.y), steady])


func _test_contact_energy() -> void:
	# A quarter car standing on its tyre and shaken sideways: the tread only ever takes energy out.
	var spec := KIRI.packed()
	var u := Vector2.ZERO
	var v := 0.5
	var start := 0.5 * 312.0 * v * v
	var most := 0.0
	for i in 600:
		var touch := TyreModel.contact(spec, u, 0.0, 0.0, v, 3000.0, 1.0, DT)
		u = Vector2(touch.z, touch.w)
		v += touch.y / 312.0 * DT
		var py := KIRI.relaxation * tan(KIRI.peak_angle)
		var stiff := TyreModel.peak(spec, 3000.0, 1.0) * spec[CarSpec.TYRE_B] \
			* spec[CarSpec.TYRE_SHAPE] / py
		var now := 0.5 * 312.0 * v * v + 0.5 * stiff * pow(u.y * py, 2.0)
		most = maxf(most, now)
	expect(most <= start * 1.01 and absf(v) < 0.01,
		"shaken sideways at a stand, the tread stills it and never adds energy: at most %.1f J of "
		% most + "%.1f, %.4f m/s left" % [start, v])


func _test_suspension() -> void:
	var spec := KIRI.packed()
	var corners := Suspension.new()
	var on := PackedByteArray([1, 1, 1, 0])
	var rest := corners.loads(spec, PackedFloat64Array([0.05, 0.05, 0.05, 0.0]), on, DT)
	expect(is_equal_approx(rest[0], KIRI.spring_rate * 0.05) and rest[3] == 0.0,
		"a still corner carries its spring's load, one in the air none")
	var rising := corners.loads(spec, PackedFloat64Array([0.06, 0.05, 0.05, 0.0]), on, DT)
	expect(rising[0] > KIRI.spring_rate * 0.06 and rising[1] < KIRI.spring_rate * 0.05,
		"compressing, its damper adds and the anti-roll bar takes from the other side")


## Steers full left and right for 10 s with [param held] set: the car stays where it stood.
func _test_steered_standing(held: Dictionary) -> void:
	var ground_body := ground()
	var car: Node3D = spawn_car()
	car.held_controls = held.duplicate()
	for i in 90:
		await physics_frame
	var from: Vector3 = car.global_position
	var facing: Vector3 = -car.global_basis.z
	for i in 600:
		var controls: Dictionary = held.duplicate()
		@warning_ignore("integer_division")
		controls.steer = 1.0 if (i / 60) % 2 == 0 else -1.0
		car.held_controls = controls
		await physics_frame
	var moved := car.global_position.distance_to(from)
	var turned := rad_to_deg(facing.angle_to(-car.global_basis.z))
	expect(moved < 0.02 and turned < 0.5,
		"%s, steered full left and right for 10 s it stays put: %.3f m, %.2f°"
		% [held, moved, turned])
	car.queue_free()
	ground_body.queue_free()
	await process_frame


## Coasting in N at 10 m/s through a slalom, the car's energy never rises.
func _test_coasting_slalom() -> void:
	var ground_body := ground()
	var car: RigidBody3D = spawn_car() as RigidBody3D
	car.held_controls = {select = "N"}
	for i in 60:
		await physics_frame
	car.linear_velocity = -car.global_basis.z * 10.0
	car.reset_physics_interpolation()
	for i in 30:
		await physics_frame
	var last := _energy(car)
	var worst := 0.0
	for i in 240:
		car.held_controls = {select = "N", steer = sin(i * 0.05) * 0.6}
		await physics_frame
		var now := _energy(car)
		worst = maxf(worst, (now - last) / maxf(last, 1.0))
		last = now
	expect(worst < 0.001, "coasting through a slalom it never gains energy: at most %+.4f%% a step"
		% (worst * 100.0))
	car.queue_free()
	ground_body.queue_free()
	await process_frame


## The body's kinetic energy plus its height's, joules; the wheels' spin is small beside it.
func _energy(car: RigidBody3D) -> float:
	var spin := car.angular_velocity
	return 0.5 * car.mass * car.linear_velocity.length_squared() \
		+ 0.5 * spin.dot(car.inertia * spin) + car.mass * CarSpec.G * car.global_position.y
