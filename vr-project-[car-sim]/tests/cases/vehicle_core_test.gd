extends TestCase
## The shared vehicle core ([CarSpec], [TyreModel], [Powertrain], [Assists], [CarDynamics],
## [PlanarVehicle]), stepped by hand on flat ground with no scene: the Kiri '86 pulls, brakes and
## corners like a small sports car, its aids do their work, it repeats itself exactly, and a road
## user's two-axle car follows what its driver asks.

const KIRI := preload("res://scenarios/vehicle/specs/kiri86.tres")
const SPECS := ["hatchback", "saloon", "van", "lorry"]
const KMH_100 := 100.0 / 3.6


func run() -> void:
	_test_tyre()
	_test_powertrain()
	_test_launch()
	_test_braking()
	_test_cornering()
	_test_handbrake()
	_test_traction_control()
	_test_repeats()
	_test_planar()
	_test_specs()


func _test_tyre() -> void:
	var spec := KIRI.packed()
	var load := 3000.0
	var top := TyreModel.peak(spec, load, 1.0)
	var at_peak := TyreModel.force(spec, spec[CarSpec.PEAK_RATIO], 0.0, load, 1.0)
	expect(absf(at_peak.x - top) < 1.0, "the tyre pulls hardest at its peak slip: %.0f N" % at_peak.x)
	var spun := TyreModel.force(spec, 1.0, 0.0, load, 1.0)
	expect(spun.x < top and spun.x > top * 0.6, "and less spinning, but not nothing: %.0f" % spun.x)
	var side := TyreModel.force(spec, 0.0, 0.05, load, 1.0)
	expect(side.y < 0.0, "sliding left, the tyre pushes right")
	var both := TyreModel.force(spec, 0.08, 0.1, load, 1.0)
	expect(both.length() <= top + 1.0, "braking and turning share the grip: %.0f <= %.0f"
		% [both.length(), top])
	expect(TyreModel.force(spec, 0.1, 0.0, load, 0.5).x < at_peak.x * 0.55,
		"half the friction, half the grip")
	expect(TyreModel.peak(spec, load * 2.0, 1.0) < top * 2.0, "grip grows less than the load")


func _test_powertrain() -> void:
	var spec := KIRI.packed()
	expect(is_equal_approx(Powertrain.rpm(spec, 0.0, 1), spec[CarSpec.IDLE_RPM]),
		"standing still, the engine idles")
	expect(Powertrain.rpm(spec, 30.0, 1) > Powertrain.rpm(spec, 30.0, 5) * 3.0,
		"a low gear turns the engine faster")
	expect(Powertrain.rpm(spec, 1000.0, 1) <= spec[CarSpec.REDLINE_RPM], "never past the redline")
	expect(Powertrain.engine_torque(spec, 6400.0, 1.0) > 190.0, "full torque high in the revs")
	expect(Powertrain.engine_torque(spec, 4000.0, 0.0) < 0.0, "throttle shut, the engine brakes")
	expect(Powertrain.engine_torque(spec, spec[CarSpec.REDLINE_RPM], 1.0) <= 0.0,
		"the limiter cuts at the redline")
	var gentle := _first_change(spec, 0.2)
	var hard := _first_change(spec, 1.0)
	expect(hard > gentle * 1.5, "full throttle holds a gear longer: %.1f > %.1f m/s" % [hard, gentle])
	expect(Powertrain.drive_force_max(spec, 2.0) > Powertrain.drive_force_max(spec, 40.0) * 2.0,
		"more pull slowly, in a low gear")


## The speed, m/s, at which the automatic first changes up at [param throttle], speeding up
## steadily.
func _first_change(spec: PackedFloat64Array, throttle: float) -> float:
	var box := Gearbox.new(spec)
	box.select(Gearbox.Selector.DRIVE)
	for step in 1200:
		var speed := step * 0.025
		box.step(DT, throttle, speed)
		if box.gear != 1:
			return speed
	return INF


func _test_launch() -> void:
	var car := FlatCar.new(KIRI.packed(), Assists.preset("exam"))
	var time := car.until({throttle = 1.0}, func(c: FlatCar) -> bool: return c.vx >= KMH_100, 20.0)
	expect(time > 6.0 and time < 9.5, "0 to 100 km/h at full throttle: %.2f s" % time)
	expect(car.dyn.gear >= 3, "through the gears: in %d" % car.dyn.gear)


func _test_braking() -> void:
	for with_abs in [true, false]:
		var aids := Assists.preset("exam")
		aids[Assists.ABS] = 1.0 if with_abs else 0.0
		var car := FlatCar.new(KIRI.packed(), aids)
		car.vx = KMH_100
		car.spin_up()
		var locked := [0]
		var start := car.x
		var time := car.until({brake = 1.0}, func(c: FlatCar) -> bool:
			if c.dyn.spin[0] == 0.0 and c.vx > 1.0:
				locked[0] += 1
			return c.vx <= 0.05, 10.0)
		var distance := car.x - start
		if with_abs:
			expect(distance > 30.0 and distance < 45.0,
				"from 100 km/h with ABS, stops in %.1f m (%.2f s)" % [distance, time])
			expect(locked[0] < 10, "without locking the fronts for long: %d steps" % locked[0])
		else:
			expect(locked[0] > 30, "without ABS, the fronts lock: %d steps" % locked[0])


func _test_cornering() -> void:
	var car := FlatCar.new(KIRI.packed(), Assists.preset("sim"))
	car.vx = 20.0
	car.spin_up()
	var most := 0.0
	for i in 300:
		var steer := minf(i * 0.0006, 0.09)
		var hold := clampf((20.0 - car.vx) * 0.5 + 0.25, 0.0, 1.0)
		car.tick({throttle = hold, steer = steer})
		most = maxf(most, absf(car.ay))
	expect(most > 7.5 and most < 11.0, "it corners at up to %.2f m/s² at 72 km/h" % most)


func _test_handbrake() -> void:
	var car := FlatCar.new(KIRI.packed(), Assists.preset("sim"))
	car.vx = 15.0
	car.spin_up()
	for i in 20:
		car.tick({steer = 0.15, throttle = 0.3})
	var before := car.yaw
	for i in 60:
		car.tick({steer = 0.15, handbrake = 1.0})
	expect(car.dyn.spin[CarDynamics.RL] == 0.0, "the handbrake locks the rears")
	expect(car.yaw - before > deg_to_rad(35.0), "and the car swings round: %.0f°"
		% rad_to_deg(car.yaw - before))


func _test_traction_control() -> void:
	var slips := []
	for title in ["sim", "exam"]:
		var car := FlatCar.new(KIRI.packed(), Assists.preset(title))
		car.mu = 0.35
		var most := 0.0
		for i in 120:
			car.tick({throttle = 1.0})
			most = maxf(most, car.dyn.ratio[CarDynamics.RL])
		slips.append(most)
	expect(slips[1] < slips[0] * 0.7, "traction control keeps the wheelspin down on a slippery road: "
		+ "%.2f against %.2f" % [slips[1], slips[0]])


func _test_repeats() -> void:
	var runs := []
	for k in 2:
		var car := FlatCar.new(KIRI.packed(), Assists.preset("sport"))
		for i in 300:
			car.tick({throttle = 1.0 if i < 200 else 0.0, brake = 1.0 if i >= 200 else 0.0,
				steer = sin(i * 0.05) * 0.1})
		runs.append([car.x, car.z, car.yaw, car.vx, car.vy, car.r])
	expect(runs[0] == runs[1], "the same controls drive the same way, exactly")


func _test_planar() -> void:
	var spec := (load("res://scenarios/vehicle/specs/saloon.tres") as CarSpec).packed()
	var state := Vector3.ZERO
	for i in 60:
		state = PlanarVehicle.step(spec, state, 0.0, 2.0, 1.0, DT)
	expect(absf(state.x - 2.0) < 0.15, "a road user pulls away as asked: %.2f m/s" % state.x)
	state = Vector3(20.0, 0.0, 0.0)
	var t := 0.0
	while state.x > 0.0 and t < 10.0:
		state = PlanarVehicle.step(spec, state, 0.0, -8.0, 1.0, DT)
		t += DT
	expect(t > 2.3 and t < 2.9, "and brakes hard as asked: stopped in %.2f s" % t)
	expect(state.x == 0.0, "never rolling back")
	var limited := Vector3(20.0, 0.0, 0.0)
	for i in 30:
		limited = PlanarVehicle.step(spec, limited, 0.0, -20.0, 0.4, DT)
	expect(20.0 - limited.x < 0.5 * 9.81 * 0.5 * 1.1, "no harder than a wet road holds: %.2f m/s"
		% limited.x)
	var curvature := 1.0 / 40.0
	var speed := 12.0
	state = Vector3(speed, 0.0, 0.0)
	var steer := PlanarVehicle.steer_for(spec, curvature, speed)
	for i in 240:
		state = PlanarVehicle.step(spec, state, steer, 0.0, 1.0, DT)
	var turning := state.z / maxf(state.x, 0.1)
	expect(absf(turning - curvature) < curvature * 0.12,
		"steered for a 40 m curve, it follows one: %.0f m" % (1.0 / turning))
	expect(PlanarVehicle.curve_speed(1.0 / 20.0, 3.0) < 8.0, "a tight curve calls for a slow speed")
	var slow := PlanarVehicle.step(spec, Vector3(1.0, 0.0, 0.0), 0.3, 0.0, 1.0, DT)
	expect(slow.z > 0.0 and absf(slow.y) < 0.5, "at a crawl it turns as its wheels point")


func _test_specs() -> void:
	for title: String in SPECS:
		var spec := (load("res://scenarios/vehicle/specs/%s.tres" % title) as CarSpec).packed()
		var state := Vector3.ZERO
		for i in 300:
			state = PlanarVehicle.step(spec, state, 0.0, 1.5, 1.0, DT)
		expect(state.x > 6.0, "the %s pulls away: %.1f m/s after 5 s" % [title, state.x])


## The core on flat ground, as the player's car's body would carry it: loads from the weight and
## its transfer, contact patches moving with the body, forces summed into the body's motion.
class FlatCar:
	var dyn: CarDynamics
	var spec: PackedFloat64Array
	var mu := 1.0
	var x := 0.0
	var z := 0.0
	var yaw := 0.0
	var vx := 0.0
	var vy := 0.0
	var r := 0.0
	var ax := 0.0
	var ay := 0.0
	## The car's sensors and control units, as on the player's car.
	var systems := CarSystems.new()

	func _init(p_spec: PackedFloat64Array, aids: PackedFloat64Array) -> void:
		spec = p_spec
		dyn = CarDynamics.new(spec, aids)
		dyn.gearbox.select(Gearbox.Selector.DRIVE)

	## Sets the wheels rolling at the car's speed, as if it had been driving.
	func spin_up() -> void:
		for i in 4:
			dyn.spin[i] = vx / spec[CarSpec.WHEEL_RADIUS]
		dyn.gearbox.select(Gearbox.Selector.DRIVE, vx)

	## Ticks with [param controls] until [param done] or [param limit] seconds; the time taken.
	func until(controls: Dictionary, done: Callable, limit: float) -> float:
		var t := 0.0
		while t < limit and not done.call(self):
			tick(controls)
			t += DT
		return t

	func tick(controls: Dictionary) -> void:
		var m := spec[CarSpec.MASS]
		var a := CarSpec.to_front(spec)
		var b := CarSpec.to_rear(spec)
		var l := spec[CarSpec.WHEELBASE]
		var h := spec[CarSpec.COG_HEIGHT]
		var half := spec[CarSpec.TRACK] * 0.5
		var front := m * CarSpec.G * b / l - m * ax * h / l
		var rear := m * CarSpec.G - front
		var shift := m * ay * h / spec[CarSpec.TRACK]
		var loads := PackedFloat64Array([front * 0.5 - shift * b / l, front * 0.5 + shift * b / l,
			rear * 0.5 - shift * a / l, rear * 0.5 + shift * a / l])
		var steer := float(controls.get("steer", 0.0))
		var fronts := Steering.ackermann(spec, steer)
		var turned := PackedFloat64Array([fronts.x, fronts.y, 0.0, 0.0])
		controls.angles = turned
		var along := PackedFloat64Array()
		var across := PackedFloat64Array()
		var places: Array[Vector2] = [Vector2(a, half), Vector2(a, -half), Vector2(-b, half),
			Vector2(-b, -half)]
		for i in 4:
			var p := places[i]
			var v := Vector2(vx - r * p.y, vy + r * p.x)
			var angle := turned[i]
			along.append(v.x * cos(angle) + v.y * sin(angle))
			across.append(-v.x * sin(angle) + v.y * cos(angle))
		systems.sense(dyn, {yaw_rate = r, specific_force = Vector3(ax, ay, CarSpec.G)},
			{steer_angle = steer, throttle = controls.get("throttle", 0.0),
			brake = controls.get("brake", 0.0), handbrake = controls.get("handbrake", 0.0)})
		systems.decide(spec, dyn.aids, DT)
		dyn.step(DT, controls, loads, along, across, PackedFloat64Array([mu, mu, mu, mu]),
			systems.signals)
		# Rolling resistance is the tyres' own, in the wheel solve; only the air acts on the body.
		var fx := -0.5 * CarSpec.AIR * spec[CarSpec.DRAG_AREA] * vx * absf(vx)
		var fy := 0.0
		var moment := 0.0
		for i in 4:
			var angle := turned[i]
			var f := dyn.force[i]
			var wx := f.x * cos(angle) - f.y * sin(angle)
			var wy := f.x * sin(angle) + f.y * cos(angle)
			fx += wx
			fy += wy
			moment += places[i].x * wy - places[i].y * wx
		ax = fx / m
		ay = fy / m
		vx += (ax + r * vy) * DT
		vy += (ay - r * vx) * DT
		r += moment / spec[CarSpec.YAW_INERTIA] * DT
		yaw += r * DT
		x += (vx * cos(yaw) - vy * sin(yaw)) * DT
		z += (vx * sin(yaw) + vy * cos(yaw)) * DT
