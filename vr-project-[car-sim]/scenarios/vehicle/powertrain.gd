class_name Powertrain
extends RefCounted
## The engine and gearing of a [CarSpec], as pure functions: the gears' ratios, the engine's
## torque over its revolutions, engine braking with the throttle shut, a rev limiter, and the most
## drive a car can put down at a speed. The choice of gear is the [Gearbox]'s; the engine's spin
## and its clutch are [CarDynamics]'. Gears are 1 and up forward, -1 reverse, 0 neutral.
## Allocation free, for any thread.


## The ratio from the engine to the wheels in [param gear], final drive included; 0 in neutral,
## negative in reverse.
static func ratio(spec: PackedFloat64Array, gear: int) -> float:
	if gear == 0:
		return 0.0
	if gear < 0:
		return -spec[CarSpec.REVERSE_RATIO] * spec[CarSpec.FINAL_DRIVE]
	var top := int(spec[CarSpec.GEAR_COUNT])
	return spec[CarSpec.GEARS + clampi(gear, 1, top) - 1] * spec[CarSpec.FINAL_DRIVE]


static func gear_count(spec: PackedFloat64Array) -> int:
	return int(spec[CarSpec.GEAR_COUNT])


## The engine's revolutions with the driven wheels turning at [param wheel_spin] rad/s in
## [param gear], before the clutch: idle at least, the redline at most.
static func rpm(spec: PackedFloat64Array, wheel_spin: float, gear: int) -> float:
	var through := absf(wheel_spin * ratio(spec, gear)) / CarSpec.RPM
	return clampf(through, spec[CarSpec.IDLE_RPM], spec[CarSpec.REDLINE_RPM])


## The engine's full-throttle torque at [param at_rpm], Nm, from the spec's curve.
static func curve(spec: PackedFloat64Array, at_rpm: float) -> float:
	var first := CarSpec.GEARS + int(spec[CarSpec.GEAR_COUNT])
	var x := clampf(at_rpm / CarSpec.CURVE_STEP, 0.0, CarSpec.CURVE_SAMPLES - 1.0)
	var i := mini(int(x), CarSpec.CURVE_SAMPLES - 2)
	return lerpf(spec[first + i], spec[first + i + 1], x - i)


## The engine's friction with the throttle shut at any revolutions, Nm, besides the engine
## braking that grows with them.
const FRICTION := 10.0
## How far below the redline the limiter cuts, rpm: a step's climb, so the revolutions settle at the
## redline rather than past it.
const LIMITER_BAND := 100.0


## The engine's torque at [param at_rpm] with [param throttle] (0 to 1), Nm: the curve's share
## with the throttle, less its friction and engine braking, which grows with the revolutions and
## fades with the throttle; nothing from the limiter's cut up (the limiter).
static func engine_torque(spec: PackedFloat64Array, at_rpm: float, throttle: float) -> float:
	var drag := (FRICTION + spec[CarSpec.ENGINE_BRAKING] * at_rpm / spec[CarSpec.REDLINE_RPM]) \
		* (1.0 - throttle)
	if at_rpm >= spec[CarSpec.REDLINE_RPM] - LIMITER_BAND:
		return -drag
	return curve(spec, at_rpm) * throttle - drag


## The torque the engine sends to the driven wheels altogether in [param gear], Nm: the engine's
## torque through the gearbox, the final drive and their losses. Signed with the wheels' forward
## spin.
static func wheel_torque(spec: PackedFloat64Array, at_rpm: float, throttle: float,
		gear: int) -> float:
	return through(spec, engine_torque(spec, at_rpm, throttle), ratio(spec, gear))


## The engine's [param torque] at the wheels through [param gearing], Nm: the losses take from
## the drive, and add to the engine's braking.
static func through(spec: PackedFloat64Array, torque: float, gearing: float) -> float:
	var out := torque * gearing
	return out * spec[CarSpec.EFFICIENCY] if torque > 0.0 else out / spec[CarSpec.EFFICIENCY]


## The most forward force the engine can put on the road at [param speed] m/s in its best gear,
## newtons, tyres aside. Road users drive with it.
static func drive_force_max(spec: PackedFloat64Array, speed: float) -> float:
	var spin := maxf(speed, 0.0) / spec[CarSpec.WHEEL_RADIUS]
	var best := 0.0
	for gear in range(1, gear_count(spec) + 1):
		var through := absf(spin * ratio(spec, gear)) / CarSpec.RPM
		if through > spec[CarSpec.REDLINE_RPM]:
			continue
		var at := maxf(through, spec[CarSpec.LAUNCH_RPM])
		best = maxf(best, wheel_torque(spec, at, 1.0, gear))
	return best / spec[CarSpec.WHEEL_RADIUS]
