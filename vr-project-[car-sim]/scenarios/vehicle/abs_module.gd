class_name AbsModule
extends RefCounted
## The player's car's ABS module, which also runs traction and stability control, as a real one
## does. It reads only [CarSignals] (the wheel speeds, the gyro, the accelerometer, the steering
## angle, the pedals) and writes back its estimates and what it asks of the brakes and the engine.
## It never sees the tyres' true slip or the road's friction: it estimates them.
##
## The car's speed over the road is estimated from the wheels. Braking, it follows the fastest
## wheel, or what the accelerometer's deceleration leaves of the last estimate when that is faster,
## and never falls faster than a car can brake ([constant DECEL_LIMIT]), so locking wheels do not
## drag it down; a wheel speeding back up pulls it up at once. Driving, it follows the undriven
## wheels; a car driven at every wheel has none, so it follows the slowest, never rising faster
## than the car can accelerate ([constant ACCEL_LIMIT]), so spinning wheels do not drag it up. Each wheel's slip is its speed against that. The body's sideways
## drift is integrated from the accelerometer and the gyro, leaking away, for the rear axle's slip
## angle; the road's grip is judged from the most the accelerometer has felt lately. Its valves
## ease every brake on a locking wheel, stability control's own as well as the driver's.

## The most the estimated speed falls in a second braking, and rises driving on a car driven at
## every wheel, m/s².
const DECEL_LIMIT := 1.1 * CarSpec.G
const ACCEL_LIMIT := 1.0 * CarSpec.G
## Seconds the drift estimate takes to leak most of the way back to none, and the speed below
## which there is none.
const DRIFT_LEAK := 1.0
const DRIFT_SPEED := 3.0
## The grip assumed with nothing felt, as a share of the tyres' grip on dry asphalt, and the
## seconds a grip felt takes to fade back toward it.
const GRIP_FLOOR := 0.5
const GRIP_FADE := 3.0
## The torque stability control adds to one wheel's brake per rad/s of yaw error, and its most, Nm.
const ESC_TORQUE := 5000.0
const ESC_MOST := 1800.0

## The estimated grip, as a share of the tyres' grip on dry asphalt.
var grip := GRIP_FLOOR

var _drift := 0.0
var _started := false


## One step of [param dt] seconds for the car [param spec] with the driver's [param aids]
## ([Assists]): reads and writes [param signals].
func step(signals: CarSignals, spec: PackedFloat64Array, aids: PackedFloat64Array,
		dt: float) -> void:
	var w := signals.wheel_speed
	var braking := signals.brake_switch or signals.handbrake_switch
	var target := 0.0
	if braking:
		for i in 4:
			if absf(w[i]) > absf(target):
				target = w[i]
		# Every wheel may be slipping: the speed the accelerometer's deceleration leaves is the
		# better guess while it is faster than the fastest wheel.
		var predicted := signals.vehicle_speed + signals.accel.x * dt
		if absf(predicted) > absf(target) and signf(predicted) == signf(signals.vehicle_speed):
			target = predicted
	else:
		target = _free_rolling(w, spec)
	var last := signals.vehicle_speed
	var speed := target
	if not _started:
		# Switched on: the wheels as they are.
		_started = true
	elif braking and absf(target) < absf(last):
		speed = move_toward(last, target, DECEL_LIMIT * dt)
	elif not braking and CarSpec.driven_count(spec) == 4 and absf(target) > absf(last):
		speed = move_toward(last, target, ACCEL_LIMIT * dt)
	signals.vehicle_speed = speed
	var heading := signf(speed) if speed != 0.0 else 1.0
	for i in 4:
		signals.wheel_slip[i] = TyreModel.slip_ratio(w[i], speed)

	# The drift across the car: what the accelerometer feels sideways beyond what the turn needs.
	if absf(speed) > DRIFT_SPEED:
		_drift += (signals.accel.y - signals.yaw_rate * speed) * dt
		_drift *= exp(-dt / DRIFT_LEAK)
	else:
		_drift = 0.0
	signals.rear_slip = TyreModel.slip_angle(speed,
		_drift - signals.yaw_rate * CarSpec.to_rear(spec))

	var felt := signals.accel.length() / (CarSpec.G * spec[CarSpec.GRIP]) * 1.15
	grip = maxf(Damped.follow(grip, GRIP_FLOOR, dt, GRIP_FADE), felt)
	grip = clampf(grip, GRIP_FLOOR, 1.0)

	# ABS: eases each wheel's footbrake while it locks.
	signals.abs_active = false
	for i in 4:
		var scale := 1.0
		if signals.brake_switch:
			scale = Assists.brake(aids, spec, 1.0, signals.wheel_slip[i] * heading)
			signals.abs_active = signals.abs_active or scale < 1.0
		signals.brake_scale[i] = scale

	# Traction control: cuts the engine while a driven wheel runs ahead of the road.
	var drive_slip := 0.0
	for i in 4:
		if CarSpec.driven(spec, i):
			drive_slip = maxf(drive_slip, signals.wheel_slip[i] * (signf(w[i]) if w[i] != 0.0 else 1.0))
	signals.throttle_scale = Assists.throttle(aids, spec, 1.0, drive_slip)
	signals.tcs_active = signals.throttle_position > 0.01 and signals.throttle_scale < 0.999

	# Stability control: brakes one wheel to turn the car back to what the steering asks, and eases
	# the engine. Turning more than the steering asks, the rear slides: brake the outer front;
	# turning less, the front ploughs on: brake the inner rear.
	var error := Assists.yaw_error(aids, spec, speed, signals.steer_angle, signals.yaw_rate, grip)
	signals.esc_active = error != 0.0
	for i in 4:
		signals.brake_extra[i] = 0.0
	if error != 0.0:
		signals.throttle_scale *= clampf(1.0 - absf(error) * 2.0, 0.2, 1.0)
		var asked := Assists.asked_yaw(spec, speed, signals.steer_angle)
		var oversteer := absf(signals.yaw_rate) > absf(asked)
		var right := error > 0.0
		var wheel := (CarDynamics.FR if right else CarDynamics.FL) if oversteer \
			else (CarDynamics.RR if right else CarDynamics.RL)
		signals.brake_extra[wheel] = minf(absf(error) * ESC_TORQUE, ESC_MOST)
		# The same valves ease its own braking on a wheel that locks, as the driver's.
		var easing := Assists.brake(aids, spec, 1.0, signals.wheel_slip[wheel] * heading)
		signals.brake_extra[wheel] *= easing
		signals.abs_active = signals.abs_active or easing < 1.0


## The speed the wheels that roll free say: the undriven ones' mean, or on a car driven at every
## wheel the slowest.
static func _free_rolling(w: PackedFloat64Array, spec: PackedFloat64Array) -> float:
	var total := 0.0
	var count := 0
	var slowest := INF
	for i in 4:
		if not CarSpec.driven(spec, i):
			total += w[i]
			count += 1
		if absf(w[i]) < absf(slowest):
			slowest = w[i]
	return total / count if count > 0 else slowest

