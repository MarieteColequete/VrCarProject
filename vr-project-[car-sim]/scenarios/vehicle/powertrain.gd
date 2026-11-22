class_name Powertrain
extends RefCounted
## The engine and gearbox of a [CarSpec], as pure functions: the engine's torque over its
## revolutions, a clutch that slips to pull away, engine braking with the throttle shut, a rev
## limiter, the automatic gearbox's choice of gear, and the most drive a car can put down at a
## speed. Gears are 1 and up forward, -1 reverse, 0 neutral. Allocation free, for any thread.


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
	var through := absf(wheel_spin * ratio(spec, gear)) * 60.0 / TAU
	return clampf(through, spec[CarSpec.IDLE_RPM], spec[CarSpec.REDLINE_RPM])


## The engine's revolutions with the clutch: pulling away, it slips and the engine runs up toward
## the launch revolutions with the throttle.
static func engine_rpm(spec: PackedFloat64Array, wheel_spin: float, gear: int,
		throttle: float) -> float:
	var through := rpm(spec, wheel_spin, gear)
	if gear == 0:
		return lerpf(spec[CarSpec.IDLE_RPM], spec[CarSpec.REDLINE_RPM], throttle * 0.9)
	var slipping := lerpf(spec[CarSpec.IDLE_RPM], spec[CarSpec.LAUNCH_RPM], throttle)
	return maxf(through, slipping)


## The engine's full-throttle torque at [param at_rpm], Nm, from the spec's curve.
static func curve(spec: PackedFloat64Array, at_rpm: float) -> float:
	var first := CarSpec.GEARS + int(spec[CarSpec.GEAR_COUNT])
	var x := clampf(at_rpm / CarSpec.CURVE_STEP, 0.0, CarSpec.CURVE_SAMPLES - 1.0)
	var i := mini(int(x), CarSpec.CURVE_SAMPLES - 2)
	return lerpf(spec[first + i], spec[first + i + 1], x - i)


## The engine's torque at [param at_rpm] with [param throttle] (0 to 1), Nm: the curve's share
## with the throttle, less engine braking that grows with the revolutions and fades with the
## throttle; nothing past the redline (the limiter).
static func engine_torque(spec: PackedFloat64Array, at_rpm: float, throttle: float) -> float:
	var drag := spec[CarSpec.ENGINE_BRAKING] * at_rpm / spec[CarSpec.REDLINE_RPM] \
		* (1.0 - throttle)
	if at_rpm >= spec[CarSpec.REDLINE_RPM] - 1.0:
		return -drag
	return curve(spec, at_rpm) * throttle - drag


## The torque the engine sends to the driven wheels altogether in [param gear], Nm: the engine's
## torque through the gearbox, the final drive and their losses. Signed with the wheels' forward
## spin.
static func wheel_torque(spec: PackedFloat64Array, at_rpm: float, throttle: float,
		gear: int) -> float:
	var engine := engine_torque(spec, at_rpm, throttle)
	var through := engine * ratio(spec, gear)
	# The losses take from the drive, and add to the engine's braking.
	return through * spec[CarSpec.EFFICIENCY] if engine > 0.0 \
		else through / spec[CarSpec.EFFICIENCY]


## The gear to be in after [param gear] at [param speed] m/s with [param throttle]: reverse while
## moving back, first from a stop, up past the change-up revolutions (which rise with the
## throttle), down below the change-down revolutions, and down for a kick when the throttle goes
## to the floor with room below the redline.
static func next_gear(spec: PackedFloat64Array, gear: int, speed: float, throttle: float) -> int:
	if speed < -0.05:
		return -1
	if gear <= 0:
		return 1
	var spin := speed / spec[CarSpec.WHEEL_RADIUS]
	var now := rpm(spec, spin, gear)
	var t := clampf(throttle, 0.0, 1.0)
	var up := lerpf(spec[CarSpec.UP_GENTLE], spec[CarSpec.UP_FULL], t * t)
	if now > up and gear < gear_count(spec):
		return gear + 1
	if gear > 1:
		var lower := rpm(spec, spin, gear - 1)
		if now < spec[CarSpec.DOWN_RPM] and lower < up * 0.9:
			return gear - 1
		if t > 0.95 and lower < spec[CarSpec.UP_FULL] * 0.85:
			return gear - 1
	return gear


## The most forward force the engine can put on the road at [param speed] m/s in its best gear,
## newtons, tyres aside. Road users drive with it.
static func drive_force_max(spec: PackedFloat64Array, speed: float) -> float:
	var spin := maxf(speed, 0.0) / spec[CarSpec.WHEEL_RADIUS]
	var best := 0.0
	for gear in range(1, gear_count(spec) + 1):
		var through := absf(spin * ratio(spec, gear)) * 60.0 / TAU
		if through > spec[CarSpec.REDLINE_RPM]:
			continue
		var at := maxf(through, spec[CarSpec.LAUNCH_RPM])
		best = maxf(best, wheel_torque(spec, at, 1.0, gear))
	return best / spec[CarSpec.WHEEL_RADIUS]


## The gear as the cluster shows it: P parked on the handbrake, R, N standing still, or the gear.
static func gear_letter(gear: int, speed: float, handbrake: bool) -> String:
	if handbrake and absf(speed) < 0.1:
		return "P"
	if gear < 0:
		return "R"
	if gear == 0 or absf(speed) < 0.1:
		return "N"
	return str(gear)
