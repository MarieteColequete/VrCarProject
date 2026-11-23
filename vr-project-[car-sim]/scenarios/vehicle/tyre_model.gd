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
## The patch speed, m/s, below which a sliding tyre's grip no longer falls with the slide: a
## spinning wheel on a car standing still slides at its peak's falloff, not past it.
const SLIDE_FLOOR := 0.5
## The tread's damping as a share of critical for a quarter of the car on it, and the patch speed,
## m/s, below which it acts, fading in as the rolling's own relaxation fades out.
const DAMPING := 0.7
const DAMPED_BELOW := 3.0


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


## The tread's contact with the road for one step of [param dt] seconds, as a brush with
## relaxation (Pacejka's transient tyre): the tread deflects only as its contact patch slides over
## the road, the slide being the tread's speed [param tread] against the road's [param along] and
## the patch's sideways speed [param across] (m/s, the wheel's frame, across to the left); rolling
## along, the deflection relaxes over [constant CarSpec.RELAXATION] metres. The force follows the
## deflection up the magic formula to its peak; past it the tread slides, holding only its peak
## deflection, and its grip falls with how fast it slides. So a still patch pushes nothing however
## the wheel is turned, a held wheel grips as static friction, and rolling at speed the force
## settles to [method force] at the slip. [param deflect] is the last step's deflection, as a share
## of the peak's in each direction. Integrated backward, so it cannot add energy.
## Returns [code]Vector4(along force, across force, deflection along, deflection across)[/code],
## newtons and shares; the across force is to the left.
static func contact(spec: PackedFloat64Array, deflect: Vector2, tread: float, along: float,
		across: float, load: float, mu: float, dt: float) -> Vector4:
	var top := peak(spec, load, mu)
	if top <= 0.0:
		return Vector4.ZERO
	var sigma := spec[CarSpec.RELAXATION]
	var tan_peak := tan(spec[CarSpec.PEAK_ANGLE])
	var px := sigma * spec[CarSpec.PEAK_RATIO]
	var py := sigma * tan_peak
	var slide := tread - along
	var speed := sqrt(along * along + across * across)
	var relax := 1.0 + speed * dt / sigma
	var u := Vector2((deflect.x + slide * dt / px) / relax, (deflect.y + across * dt / py) / relax)
	var b := spec[CarSpec.TYRE_B]
	var shape := spec[CarSpec.TYRE_SHAPE]
	var size := u.length()
	var f := Vector2.ZERO
	if size > 1.0:
		u /= size
		var sliding := Vector2(slide / spec[CarSpec.PEAK_RATIO], across / tan_peak).length() \
			/ maxf(speed, SLIDE_FLOOR)
		f = u * top * magic(maxf(sliding, 1.0), b, shape)
	elif size > 0.0:
		f = u * (top * magic(size, b, shape) / size)
		# The tread's own damping, which stills it where rolling cannot relax it: slowly.
		var still := clampf(1.0 - speed / DAMPED_BELOW, 0.0, 1.0)
		if still > 0.0:
			var quarter := spec[CarSpec.MASS] * 0.25
			var stiff := top * b * shape
			var damp := Vector2(2.0 * DAMPING * sqrt(stiff / px * quarter) * px,
				2.0 * DAMPING * sqrt(stiff / py * quarter) * py) * still
			f += (u - deflect) / dt * damp
			f = f.limit_length(top)
	return Vector4(f.x, -f.y, u.x, u.y)


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
