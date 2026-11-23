extends TestCase
## The engine's states in [CarDynamics], stepped by hand: off, turned over by the starter until it
## catches, and running; the key that switches it off; the stalls a gear forced on it causes (the
## wrong way at speed, the manual's let out clutch dragging it down, a change down past the
## redline); the park pawl ratcheting at speed; and a car spawned as its [CarStart] says.

const KIRI := preload("res://scenarios/vehicle/specs/kiri86.tres")
const CAR := preload("res://scenarios/scenes/debug_car.tscn")
const Core := preload("res://tests/cases/vehicle_core_test.gd")


func run() -> void:
	_test_starter()
	_test_switch_off()
	_test_off()
	_test_wrong_way()
	_test_lugging()
	_test_over_rev()
	_test_pawl()
	await _test_car_start()


func _test_starter() -> void:
	var dyn := _parked()
	dyn.place(false, Gearbox.Selector.PARK)
	expect(dyn.rpm == 0.0 and dyn.engine == CarDynamics.EngineState.OFF, "placed off, it reads 0 rpm")
	var revs := _air(dyn, {starter = true}, 30)
	expect(dyn.engine == CarDynamics.EngineState.CRANKING and revs[-1] > 150.0 and revs[-1] < 300.0,
		"the key held turns it over at the starter's revolutions: %.0f" % revs[-1])
	_air(dyn, {}, 1)
	expect(dyn.engine == CarDynamics.EngineState.OFF, "let go after half a second, it has not caught")
	var held := 0
	while dyn.engine != CarDynamics.EngineState.RUNNING and held < 200:
		_air(dyn, {starter = true}, 1)
		held += 1
	expect(absf(held * DT - KIRI.crank_time) < 0.05,
		"held, it catches after %.1f s of cranking: %.2f s" % [KIRI.crank_time, held * DT])
	revs = _air(dyn, {starter = true}, 60)
	expect(dyn.engine == CarDynamics.EngineState.RUNNING and absf(revs[-1] - KIRI.idle_rpm) < 60.0,
		"and runs up to idle, the key still held doing nothing more: %.0f" % revs[-1])
	var drive := _parked()
	drive.place(false, Gearbox.Selector.DRIVE)
	_air(drive, {starter = true}, 1)
	expect(drive.start_refused and drive.engine == CarDynamics.EngineState.OFF,
		"in D the starter is refused")
	_air(drive, {starter = true}, 90)
	expect(drive.engine == CarDynamics.EngineState.OFF, "however long the key is held")
	var manual := CarDynamics.new(KIRI.packed(), Assists.preset("sim"), true)
	manual.place(false, Gearbox.Selector.DRIVE)
	_air(manual, {starter = true}, 90)
	expect(manual.engine == CarDynamics.EngineState.OFF, "nor does the manual start in gear")
	manual.gearbox.select(Gearbox.Selector.NEUTRAL)
	_air(manual, {}, 1)
	_air(manual, {starter = true}, 90)
	expect(manual.engine == CarDynamics.EngineState.RUNNING, "but does in neutral")


func _test_switch_off() -> void:
	var dyn := _parked()
	_air(dyn, {starter = true}, 1)
	expect(dyn.engine == CarDynamics.EngineState.OFF, "a press switches a running engine off")
	_air(dyn, {starter = true}, 120)
	expect(dyn.engine == CarDynamics.EngineState.OFF,
		"and held on, the key does not start it again until let go")
	var revs := _air(dyn, {}, 120)
	expect(revs[-1] < 1.0, "off, the revolutions run down to nothing: %.0f" % revs[-1])


func _test_off() -> void:
	var car := Core.FlatCar.new(KIRI.packed(), Assists.preset("sim"))
	car.dyn.place(false, Gearbox.Selector.DRIVE)
	car.until({throttle = 1.0}, func(_c) -> bool: return false, 2.0)
	expect(absf(car.vx) < 0.01 and car.dyn.rpm == 0.0,
		"off, the throttle in D moves nothing: %.2f m/s" % car.vx)


func _test_wrong_way() -> void:
	var fast := Core.FlatCar.new(KIRI.packed(), Assists.preset("sim"))
	fast.vx = 10.0
	fast.spin_up()
	fast.tick({})
	fast.tick({select = Gearbox.Selector.REVERSE})
	expect(fast.dyn.stalled and fast.dyn.engine == CarDynamics.EngineState.OFF,
		"R at 36 km/h rolling forward stalls the engine")
	expect(fast.dyn.spin[CarDynamics.RL] * KIRI.wheel_radius < fast.vx - 3.0,
		"with a jolt that checks the driven wheels: %.1f m/s at the tread" %
		(fast.dyn.spin[CarDynamics.RL] * KIRI.wheel_radius))
	var slow := Core.FlatCar.new(KIRI.packed(), Assists.preset("sim"))
	slow.vx = 0.8
	slow.spin_up()
	slow.tick({})
	var stalled := false
	slow.tick({select = Gearbox.Selector.REVERSE})
	for i in 240:
		stalled = stalled or slow.dyn.stalled
		slow.tick({})
	expect(not stalled and slow.dyn.engine == CarDynamics.EngineState.RUNNING and slow.vx < 0.0,
		"R at a crawl forward does not stall: the converter stops the car and backs it: %.2f m/s"
		% slow.vx)
	var back := Core.FlatCar.new(KIRI.packed(), Assists.preset("sim"))
	back.dyn.gearbox.select(Gearbox.Selector.REVERSE)
	back.vx = -6.0
	back.spin_up()
	back.dyn.gearbox.select(Gearbox.Selector.REVERSE)
	back.tick({})
	back.tick({select = Gearbox.Selector.DRIVE})
	expect(back.dyn.stalled, "D rolling backward at 22 km/h stalls it")


func _test_lugging() -> void:
	var car := _manual_flat(8.0, 3)
	var stalled := [false]
	car.until({brake = 0.6}, func(c) -> bool:
		stalled[0] = stalled[0] or c.dyn.stalled
		return c.vx < 0.05, 10.0)
	expect(stalled[0] and car.dyn.engine == CarDynamics.EngineState.OFF,
		"the manual braked to a stop in 3rd, never put in neutral, stalls")
	var pull := Core.FlatCar.new(KIRI.packed(), Assists.preset("sim"))
	pull.dyn.manual = true
	pull.dyn.gearbox.select(Gearbox.Selector.DRIVE)
	stalled = [false]
	pull.until({throttle = 0.4}, func(c) -> bool:
		stalled[0] = stalled[0] or c.dyn.stalled
		return false, 3.0)
	expect(not stalled[0] and pull.dyn.engine == CarDynamics.EngineState.RUNNING and pull.vx > 3.0,
		"pulling away in first with throttle never stalls: %.1f m/s" % pull.vx)
	var coast := _manual_flat(15.0, 3)
	stalled = [false]
	coast.until({}, func(c) -> bool:
		stalled[0] = stalled[0] or c.dyn.stalled
		return false, 2.0)
	expect(not stalled[0] and coast.dyn.engine == CarDynamics.EngineState.RUNNING,
		"coasting in 3rd at 54 km/h with the throttle shut keeps running")


func _test_over_rev() -> void:
	var car := _manual_flat(30.0, 5)
	car.tick({})
	expect(not car.dyn.stalled, "5th at 108 km/h runs")
	car.tick({shift = -1})
	car.tick({shift = -1})
	expect(not car.dyn.stalled, "4th and 3rd too")
	car.tick({shift = -1})
	expect(car.dyn.gear == 2 and car.dyn.stalled,
		"2nd at 108 km/h drags the engine past its redline, and it stalls")


func _test_pawl() -> void:
	var car := Core.FlatCar.new(KIRI.packed(), Assists.preset("sim"))
	car.vx = 3.0
	car.spin_up()
	car.tick({})
	car.tick({select = Gearbox.Selector.PARK})
	expect(car.dyn.gearbox.letter() == "P" and car.vx > 2.9,
		"P rolling at 11 km/h: the pawl ratchets rather than locking: %.2f m/s" % car.vx)
	car.until({brake = 0.3}, func(c) -> bool: return c.vx < 0.05, 5.0)
	car.until({throttle = 1.0}, func(_c) -> bool: return false, 1.0)
	expect(absf(car.vx) < 0.05, "slowed, it drops in and holds the car on throttle: %.2f m/s"
		% car.vx)


func _test_car_start() -> void:
	var floor := ground()
	var start := CarStart.new()
	var car: Node3D = CAR.instantiate()
	car.set(&"start", start)
	root.add_child(car)
	for i in 20:
		await physics_frame
	car.held_controls = {throttle = 1.0}
	for i in 60:
		await physics_frame
	expect(car.rpm == 0.0 and car.linear_velocity.length() < 0.1
		and car.dynamics.gearbox.letter() == "P",
		"started parked with the engine off, it shows 0 rpm and the throttle moves nothing")
	car.held_controls = {ignition = true}
	for i in roundi(KIRI.crank_time / DT) + 10:
		await physics_frame
	car.held_controls = {select = "D"}
	await physics_frame
	car.held_controls = {select = "D", throttle = 0.6}
	for i in 90:
		await physics_frame
	expect(car.dynamics.engine == CarDynamics.EngineState.RUNNING and car.current_speed > 2.0,
		"the key held, then D and throttle, and it drives away: %.1f m/s" % car.current_speed)
	car.queue_free()
	var moving := CarStart.new()
	moving.speed = 15.0
	var rolling: Node3D = CAR.instantiate()
	rolling.set(&"start", moving)
	root.add_child(rolling)
	await physics_frame
	await physics_frame
	expect(rolling.current_speed > 13.0 and rolling.dynamics.engine == CarDynamics.EngineState.RUNNING
		and rolling.dynamics.gear > 1,
		"started at 54 km/h, it is rolling in D in gear %d from the first steps: %.1f m/s"
		% [rolling.dynamics.gear, rolling.current_speed])
	rolling.queue_free()
	floor.queue_free()
	await physics_frame


func _parked() -> CarDynamics:
	return CarDynamics.new(KIRI.packed(), Assists.preset("sim"))


## A manual flat car rolling at [param speed] m/s in [param gear].
func _manual_flat(speed: float, gear: int) -> Core.FlatCar:
	var car := Core.FlatCar.new(KIRI.packed(), Assists.preset("sim"))
	car.dyn.manual = true
	car.vx = speed
	car.spin_up()
	car.dyn.place(true, Gearbox.Selector.DRIVE, speed)
	while car.dyn.gear != gear:
		car.dyn.gearbox.request(signi(gear - car.dyn.gear), 0.0)
	car.dyn.gearbox.shifting = 0.0
	return car


func _air(dyn: CarDynamics, controls: Dictionary, ticks: int) -> Array:
	var revs := []
	var zero := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var mu := PackedFloat64Array([1.0, 1.0, 1.0, 1.0])
	for i in ticks:
		dyn.step(DT, controls, zero, zero, zero, mu)
		revs.append(dyn.rpm)
	return revs
