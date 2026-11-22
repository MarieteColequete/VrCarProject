class_name TyreModel
extends RefCounted
## A tyre's force at its contact patch, from how it slips: a simplified Pacejka magic formula over
## the combined slip, so braking or driving hard leaves less grip for turning (the friction
## circle). Slip ratio is how much faster the tread turns than the road goes by, over the road
## speed; slip angle is the angle between where the wheel points and where its contact patch
## goes, positive when the patch slides to the wheel's left. Pure and allocation free, for any
## thread.

## A tyre's nominal load, newtons: a quarter of a 1250 kg car's weight. Grip falls past it by the
## spec's load sensitivity.
const NOMINAL_LOAD := 3000.0


## The magic formula: the force, as a share of the peak, at a slip [param s] as a share of the
## peak slip; 1 at [code]s = 1[/code], falling off past it to [code]sin(shape·π/2)[/code].
static func magic(s: float, b: float, shape: float) -> float:
	return sin(shape * atan(b * s))


## The most force a tyre under [param load] newtons on a surface of friction [param mu] gives.
static func peak(spec: PackedFloat64Array, load: float, mu: float) -> float:
	if load <= 0.0:
		return 0.0
	var falls := 1.0 - spec[CarSpec.LOAD_SENSITIVITY] * (load / NOMINAL_LOAD - 1.0)
	return mu * spec[CarSpec.GRIP] * load * clampf(falls, 0.5, 1.2)


## The tyre's force, [code](along, across)[/code] in newtons in the wheel's frame (along forward,
## across to the left), at slip ratio [param ratio] and slip angle [param angle] under
## [param load] newtons on a surface of friction [param mu].
static func force(spec: PackedFloat64Array, ratio: float, angle: float, load: float,
		mu: float) -> Vector2:
	var top := peak(spec, load, mu)
	if top <= 0.0:
		return Vector2.ZERO
	var sx := ratio / spec[CarSpec.PEAK_RATIO]
	var sy := tan(clampf(angle, -1.5, 1.5)) / tan(spec[CarSpec.PEAK_ANGLE])
	var s := sqrt(sx * sx + sy * sy)
	if s < 0.000001:
		return Vector2.ZERO
	var f := top * magic(s, spec[CarSpec.TYRE_B], spec[CarSpec.TYRE_SHAPE]) / s
	return Vector2(f * sx, -f * sy)


## How hard the tyre works, 0 at rest to 1 at its peak and more past it: the combined slip as a
## share of the peak slip. Sound and assists read it.
static func usage(spec: PackedFloat64Array, ratio: float, angle: float) -> float:
	var sx := ratio / spec[CarSpec.PEAK_RATIO]
	var sy := tan(clampf(angle, -1.5, 1.5)) / tan(spec[CarSpec.PEAK_ANGLE])
	return sqrt(sx * sx + sy * sy)


## Slip ratio of a wheel whose tread moves at [param tread] m/s over ground passing at
## [param ground] m/s; at walking pace the ground speed is floored so it stays finite.
static func slip_ratio(tread: float, ground: float) -> float:
	return (tread - ground) / maxf(absf(ground), 1.5)


## Slip angle of a contact patch moving [param along] forward and [param across] to the left of
## the wheel, radians; floored at walking pace like [method slip_ratio].
static func slip_angle(along: float, across: float) -> float:
	return atan2(across, maxf(absf(along), 1.5))
