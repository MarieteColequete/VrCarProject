extends TestCase
## The gearbox ([Gearbox]) and the engine's own revolutions ([CarDynamics]), stepped by hand: the
## automatic's P-R-N-D lever, free to move at any speed, a gearbox that never moves between reverse and
## forward on its own however the car jitters at rest, an automatic that climbs through its gears
## without hunting, kicks down only on a pedal floored and held, holds its gear with the driven
## wheels in the air, the manual's gears and its refusal to over-rev, and an engine that revs freely
## out of gear, idles in the air with the throttle shut, and reaches its limiter, never past it.

const KIRI := preload("res://scenarios/vehicle/specs/kiri86.tres")


func run() -> void:
	_test_lever()
	_test_standing_still()
	_test_climbing()
	_test_kick_down()
	_test_airborne_gear()
	_test_manual()
	_test_letters()
	_test_engine_out_of_gear()
	_test_engine_in_the_air()
	_test_park()


func _test_lever() -> void:
	var box := Gearbox.new(KIRI.packed())
	expect(box.selector == Gearbox.Selector.PARK and box.gear == 0, "the automatic starts in park")
	expect(box.request(1, 0.0) and box.selector == Gearbox.Selector.REVERSE and box.gear == -1,
		"up a notch from park is reverse")
	expect(box.request(1, 0.0) and box.selector == Gearbox.Selector.NEUTRAL and box.gear == 0,
		"then neutral")
	expect(box.request(1, 0.0) and box.selector == Gearbox.Selector.DRIVE and box.gear == 1,
		"then drive, in first")
	expect(not box.request(1, 0.0), "drive is the end of the lever")
	expect(box.request(-1, 5.0) and box.selector == Gearbox.Selector.NEUTRAL,
		"back to neutral while moving")
	expect(box.request(-1, 5.0) and box.gear == -1,
		"and on into reverse while rolling forward: nothing is locked out")
	box.select(Gearbox.Selector.NEUTRAL)
	expect(box.request(1, -2.0) and box.gear == 1,
		"into drive while rolling backward, in first")
	box.select(Gearbox.Selector.REVERSE)
	expect(box.request(-1, 3.0) and box.selector == Gearbox.Selector.PARK,
		"into park while moving")
	expect(not box.request(-1, 3.0), "park is the other end of the lever")
	box.select(Gearbox.Selector.NEUTRAL)
	expect(box.request(1, 20.0) and box.gear > 2,
		"put into drive rolling fast, it takes a gear that suits the speed: %d" % box.gear)


func _test_standing_still() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for selector in [Gearbox.Selector.PARK, Gearbox.Selector.REVERSE, Gearbox.Selector.NEUTRAL,
			Gearbox.Selector.DRIVE]:
		var box := Gearbox.new(KIRI.packed())
		box.select(selector)
		var gear := box.gear
		var changes := 0
		for i in 600:
			box.step(DT, rng.randf_range(0.0, 0.1), rng.randf_range(-0.1, 0.1))
			if box.gear != gear:
				changes += 1
				gear = box.gear
		expect(changes == 0, "standing in %s with the car jittering, the gear never changes"
			% box.letter() + ": %d changes" % changes)


func _test_climbing() -> void:
	for throttle in [0.3, 1.0]:
		var box := Gearbox.new(KIRI.packed())
		box.select(Gearbox.Selector.DRIVE)
		var rng := RandomNumberGenerator.new()
		rng.seed = 3
		var changes := 0
		var gear := box.gear
		var speed := 0.0
		# Accelerating steadily to 40 m/s with a wavering foot.
		for i in 1200:
			speed = minf(speed + 2.5 * DT, 40.0)
			box.step(DT, clampf(throttle + rng.randf_range(-0.15, 0.15), 0.0, 1.0), speed)
			if box.gear != gear:
				changes += 1
				gear = box.gear
		expect(box.gear >= 4 and changes <= box.gear + 1,
			"throttle %.1f climbs to %d with %d changes, never hunting" % [throttle, box.gear,
				changes])
	var kick := Gearbox.new(KIRI.packed())
	kick.select(Gearbox.Selector.DRIVE, 15.0)
	for i in 120:
		kick.step(DT, 0.2, 15.0)
	var cruising := kick.gear
	for i in 60:
		kick.step(DT, 1.0, 15.0)
	expect(kick.gear < cruising, "flooring it kicks down: %d to %d" % [cruising, kick.gear])
	var slowing := Gearbox.new(KIRI.packed())
	slowing.select(Gearbox.Selector.DRIVE, 25.0)
	for i in 600:
		slowing.step(DT, 0.0, maxf(25.0 - i * DT * 8.0, 0.0))
	expect(slowing.gear == 1, "stopped, the automatic is back in first")


func _test_kick_down() -> void:
	var box := Gearbox.new(KIRI.packed())
	box.select(Gearbox.Selector.DRIVE, 25.0)
	for i in 300:
		box.step(DT, 0.2, 25.0)
	var cruising := box.gear
	# Brushed past the detent for a tenth of a second, again and again.
	for i in 240:
		box.step(DT, 1.0 if i % 30 < 6 else 0.4, 25.0)
	expect(box.gear == cruising, "brushing the pedal's end does not kick down: %d to %d"
		% [cruising, box.gear])
	for i in 60:
		box.step(DT, 1.0, 25.0)
	expect(box.gear < cruising, "pressed through and held, it does: %d to %d"
		% [cruising, box.gear])


func _test_airborne_gear() -> void:
	var box := Gearbox.new(KIRI.packed())
	box.select(Gearbox.Selector.DRIVE)
	var speed := 0.0
	# The driven wheels off the road, spinning up under full throttle.
	for i in 600:
		speed = minf(speed + 8.0 * DT, 60.0)
		box.step(DT, 1.0, speed, false)
	expect(box.gear == 1, "in the air the gear holds, however the wheels spin: %d" % box.gear)
	for i in 120:
		box.step(DT, 0.3, 20.0, true)
	expect(box.gear > 1, "back on the road it changes again: %d" % box.gear)
	var dyn := CarDynamics.new(KIRI.packed(), Assists.preset("sim"))
	dyn.gearbox.select(Gearbox.Selector.DRIVE, 0.0)
	_airborne_dyn(dyn, {throttle = 1.0}, 600)
	expect(dyn.gearbox.gear == 1 and dyn.rpm <= KIRI.redline_rpm + 60.0,
		"upside down at full throttle the car stays in first at its limiter: %d, %.0f rpm"
		% [dyn.gearbox.gear, dyn.rpm])


func _test_manual() -> void:
	var box := Gearbox.new(KIRI.packed(), true)
	expect(box.gear == 0 and box.letter() == "N", "the manual starts in neutral")
	expect(box.request(1, 0.0) and box.gear == 1, "up from neutral is first")
	expect(box.request(-1, 0.0) and box.request(-1, 0.0) and box.gear == -1,
		"down through neutral is reverse, standing still")
	box.select(Gearbox.Selector.NEUTRAL)
	expect(box.request(-1, 3.0) and box.gear == -1, "into reverse while rolling forward")
	expect(not box.request(-1, 3.0), "reverse is the bottom")
	box.select(Gearbox.Selector.DRIVE)
	for g in range(1, 5):
		box.request(1, 20.0)
	var high := box.gear
	expect(high >= 4, "up through the gears at speed: %d" % high)
	expect(box.request(-1, 30.0) and box.request(-1, 30.0) and box.request(-1, 30.0)
		and box.gear == high - 3, "changing down at 108 km/h goes through, over-rev or not")
	for i in 600:
		box.step(DT, 1.0, 30.0)
	expect(box.gear == high - 3, "the manual never changes gear by itself")


func _test_letters() -> void:
	var box := Gearbox.new(KIRI.packed())
	var letters := []
	for i in 4:
		letters.append(box.letter())
		box.request(1, 0.0)
	expect(letters == ["P", "R", "N", "1"], "the cluster shows P, R, N, then the gear: %s"
		% [letters])


func _test_engine_out_of_gear() -> void:
	var dyn := CarDynamics.new(KIRI.packed(), Assists.preset("sim"))
	dyn.gearbox.select(Gearbox.Selector.NEUTRAL)
	var revs := _airborne_dyn(dyn, {throttle = 1.0}, 120)
	var top: float = revs.max()
	expect(top > KIRI.redline_rpm * 0.95 and top <= KIRI.redline_rpm + 60.0,
		"in neutral the throttle revs the engine to its limiter, no further: %.0f" % top)
	revs = _airborne_dyn(dyn, {}, 180)
	expect(absf(revs[-1] - KIRI.idle_rpm) < 60.0, "and shut, it falls back to idle: %.0f"
		% revs[-1])
	expect(is_zero_approx(dyn.spin[CarDynamics.RL]), "the wheels never turn out of gear")


func _test_engine_in_the_air() -> void:
	var dyn := CarDynamics.new(KIRI.packed(), Assists.preset("sim"))
	dyn.gearbox.select(Gearbox.Selector.DRIVE, 20.0)
	for i in 4:
		dyn.spin[i] = 20.0 / KIRI.wheel_radius
	var revs := _airborne_dyn(dyn, {}, 240)
	var rose := 0
	for k in range(1, revs.size()):
		# A change down may meet the wheels a little above the engine; nothing more.
		if revs[k] > revs[k - 1] + 300.0:
			rose += 1
	expect(rose == 0 and absf(revs[-1] - KIRI.idle_rpm) < 60.0,
		"in the air with the throttle shut, the revs fall to idle and never flare: %.0f to %.0f"
		% [revs[0], revs[-1]])
	expect(dyn.spin[CarDynamics.RL] >= 0.0, "and the wheels never spin backward")
	revs = _airborne_dyn(dyn, {throttle = 1.0}, 240)
	var top: float = revs.max()
	expect(top > KIRI.redline_rpm * 0.9 and top <= KIRI.redline_rpm + 60.0,
		"with the throttle open, they climb to the limiter, no further: %.0f" % top)
	var climb := 0
	while climb < revs.size() and revs[climb] < KIRI.redline_rpm * 0.9:
		climb += 1
	expect(climb > 3, "at the pace of the engine's inertia, not at once: %d ticks" % climb)


func _test_park() -> void:
	var dyn := CarDynamics.new(KIRI.packed(), Assists.preset("sim"))
	var weight := KIRI.mass * CarSpec.G * 0.25
	var loads := PackedFloat64Array([weight, weight, weight, weight])
	var zero := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var mu := PackedFloat64Array([1.0, 1.0, 1.0, 1.0])
	var pushed := 0.0
	for i in 60:
		dyn.step(DT, {throttle = 1.0}, loads, zero, zero, mu, 0.0, 0.0)
		pushed = maxf(pushed, absf(dyn.force[CarDynamics.RL].x))
	expect(pushed < 1.0 and dyn.gearbox.letter() == "P",
		"in park the throttle only revs the engine: %.1f N at the rear tyres, %.0f rpm"
		% [pushed, dyn.rpm])


func _airborne_dyn(dyn: CarDynamics, controls: Dictionary, ticks: int) -> Array:
	var revs := []
	var zero := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var mu := PackedFloat64Array([1.0, 1.0, 1.0, 1.0])
	for i in ticks:
		dyn.step(DT, controls, zero, zero, zero, mu, 0.0, 0.0)
		revs.append(dyn.rpm)
	return revs
