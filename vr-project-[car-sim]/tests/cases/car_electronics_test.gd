extends TestCase
## The player's car's electronics, each layer on its own: the sensors ([CarSensors]) measuring the
## plant as hardware does, and the control units ([AbsModule], [TransmissionUnit],
## [BodyController]) deciding from [CarSignals] alone, fed here by hand with no physics behind them.

const KIRI := preload("res://scenarios/vehicle/specs/kiri86.tres")
const FL := CarDynamics.FL
const FR := CarDynamics.FR
const RL := CarDynamics.RL
const RR := CarDynamics.RR


func run() -> void:
	_test_sensors()
	_test_speed_estimate()
	_test_abs()
	_test_traction()
	_test_stability()
	_test_transmission()
	_test_lamps()


func _test_sensors() -> void:
	var dyn := CarDynamics.new(KIRI.packed(), Assists.preset("sim"))
	var signals := CarSignals.new()
	dyn.spin = PackedFloat64Array([10.0, 10.0, 0.0, 30.0])
	CarSensors.measure(signals, dyn, {yaw_rate = 0.4,
		specific_force = Vector3(-3.0, 2.0, CarSpec.G)}, {steer_angle = 0.1, brake = 0.5})
	var r := KIRI.wheel_radius
	expect(is_equal_approx(signals.wheel_speed[FL], 10.0 * r) and signals.wheel_speed[RL] == 0.0
		and is_equal_approx(signals.wheel_speed[RR], 30.0 * r),
		"each wheel speed sensor reads its own wheel's spin, a locked one nought")
	expect(is_equal_approx(signals.shaft_speed, 15.0 * r), "the shaft reads the driven wheels")
	expect(is_equal_approx(signals.yaw_rate, 0.4) and signals.accel.is_equal_approx(Vector2(-3.0, 2.0))
		and absf(signals.accel_up - CarSpec.G) < 0.001,
		"the gyro and the accelerometer read the body")
	expect(signals.brake_switch and not signals.reverse_switch,
		"the brake switch closes with the pedal; the reverse switch stays open in park")
	CarSensors.measure(signals, dyn, {specific_force = Vector3.ZERO}, {})
	expect(signals.accel_up == 0.0, "falling, the accelerometer feels nothing")
	dyn.gearbox.select(Gearbox.Selector.REVERSE)
	CarSensors.measure(signals, dyn, {}, {})
	expect(signals.reverse_switch, "in R the reverse switch closes, the car still or not")


## Signals for a car at [param wheels] m/s at each wheel.
func _signals(wheels: Array, brake := false) -> CarSignals:
	var signals := CarSignals.new()
	signals.wheel_speed = PackedFloat64Array(wheels)
	signals.brake_switch = brake
	signals.accel_up = CarSpec.G
	return signals


func _test_speed_estimate() -> void:
	var unit := AbsModule.new()
	var signals := _signals([20.0, 20.0, 20.0, 20.0])
	unit.step(signals, KIRI.packed(), Assists.preset("exam"), DT)
	expect(is_equal_approx(signals.vehicle_speed, 20.0), "switched on, it reads the wheels")
	signals.brake_switch = true
	signals.wheel_speed = PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	# Sliding on locked wheels, the car slows at about 0.9 g, as the accelerometer feels.
	signals.accel = Vector2(-9.0, 0.0)
	for i in 30:
		unit.step(signals, KIRI.packed(), Assists.preset("exam"), DT)
	var fell := 20.0 - signals.vehicle_speed
	expect(fell > 4.0 and fell < 5.5, "every wheel locked, the speed falls as the accelerometer "
		+ "feels, not to nought with the wheels: %.1f m/s in half a second" % fell)
	signals.accel = Vector2.ZERO
	signals.brake_switch = false
	signals.wheel_speed = PackedFloat64Array([12.0, 12.0, 25.0, 25.0])
	unit.step(signals, KIRI.packed(), Assists.preset("exam"), DT)
	expect(is_equal_approx(signals.vehicle_speed, 12.0),
		"driving, it reads the undriven wheels, not the spinning rears")


func _test_abs() -> void:
	var unit := AbsModule.new()
	var signals := _signals([20.0, 20.0, 20.0, 20.0], true)
	unit.step(signals, KIRI.packed(), Assists.preset("exam"), DT)
	signals.wheel_speed = PackedFloat64Array([12.0, 19.8, 19.8, 19.8])
	unit.step(signals, KIRI.packed(), Assists.preset("exam"), DT)
	expect(signals.abs_active and signals.brake_scale[FL] < 1.0 and signals.brake_scale[FR] == 1.0,
		"ABS eases the locking wheel's brake and only that one")
	var off := Assists.preset("exam")
	off[Assists.ABS] = 0.0
	unit.step(signals, KIRI.packed(), off, DT)
	expect(not signals.abs_active and signals.brake_scale[FL] == 1.0, "switched off, it does not")


func _test_traction() -> void:
	var unit := AbsModule.new()
	var signals := _signals([10.0, 10.0, 10.0, 10.0])
	signals.throttle_position = 1.0
	unit.step(signals, KIRI.packed(), Assists.preset("exam"), DT)
	signals.wheel_speed = PackedFloat64Array([10.0, 10.0, 16.0, 16.0])
	unit.step(signals, KIRI.packed(), Assists.preset("exam"), DT)
	expect(signals.tcs_active and signals.throttle_scale < 1.0,
		"the driven wheels ahead of the undriven: traction control cuts the engine: %.2f"
		% signals.throttle_scale)


func _test_stability() -> void:
	var asked := 20.0 * tan(0.05) / KIRI.wheelbase
	for turning in [1.5, asked]:
		var unit := AbsModule.new()
		var signals := _signals([20.0, 20.0, 20.0, 20.0])
		signals.steer_angle = 0.05
		signals.yaw_rate = turning
		signals.accel = Vector2(0.0, asked * 20.0)
		unit.step(signals, KIRI.packed(), Assists.preset("exam"), DT)
		if turning > 1.0:
			expect(signals.esc_active and signals.brake_extra[FR] > 0.0,
				"turning left far more than the steering asks, the rear slides: it brakes the "
				+ "outer front")
		else:
			expect(not signals.esc_active, "turning as the steering asks, it does nothing")


func _test_transmission() -> void:
	var unit := TransmissionUnit.new()
	var signals := _signals([0.0, 0.0, 0.0, 0.0])
	unit.step(signals, KIRI.packed(), DT)
	for i in 20:
		signals.shaft_speed += 0.5
		signals.wheel_speed[RL] = signals.shaft_speed
		signals.wheel_speed[RR] = signals.shaft_speed
		unit.step(signals, KIRI.packed(), DT)
	expect(signals.gear_hold, "driven wheels spinning up at 30 m/s² with the fronts still: it holds")
	var road := TransmissionUnit.new()
	var rolling := _signals([10.0, 10.0, 10.0, 10.0])
	rolling.shaft_speed = 10.0
	road.step(rolling, KIRI.packed(), DT)
	for i in 60:
		for w in 4:
			rolling.wheel_speed[w] += 3.0 * DT
		rolling.shaft_speed += 3.0 * DT
		road.step(rolling, KIRI.packed(), DT)
	expect(not rolling.gear_hold, "all four speeding up as a car does, it does not")


func _test_lamps() -> void:
	var signals := CarSignals.new()
	signals.brake_switch = true
	BodyController.step(signals)
	expect(signals.brake_light and not signals.reverse_light,
		"the brake lights follow the pedal's switch, the car still or not")
	signals.brake_switch = false
	signals.reverse_switch = true
	BodyController.step(signals)
	expect(signals.reverse_light and not signals.brake_light,
		"the reversing lights follow the reverse switch")
