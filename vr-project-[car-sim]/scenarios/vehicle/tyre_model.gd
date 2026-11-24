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


## The most force a tyre under [param wheel_load] newtons on a surface of friction [param mu] gives.
static func peak(spec: PackedFloat64Array, wheel_load: float, mu: float) -> float:
	if wheel_load <= 0.0:
		return 0.0
	var falls := 1.0 - spec[CarSpec.LOAD_SENSITIVITY] * (wheel_load / NOMINAL_LOAD - 1.0)
	return mu * spec[CarSpec.GRIP] * wheel_load * clampf(falls, 0.5, 1.2)


## The tyre's force, [code](along, across)[/code] in newtons in the wheel's frame (along forward,
## across to the left), at slip ratio [param ratio] and slip angle [param angle] under
## [param wheel_load] newtons on a surface of friction [param mu].
static func force(spec: PackedFloat64Array, ratio: float, angle: float, wheel_load: float,
		mu: float) -> Vector2:
	var top := peak(spec, wheel_load, mu)
	if top <= 0.0:
		return Vector2.ZERO
	var share := slip_share(spec, ratio, angle)
	var s := share.length()
	if s < 0.000001:
		return Vector2.ZERO
	var f := top * magic(s, spec[CarSpec.TYRE_B], spec[CarSpec.TYRE_SHAPE]) / s
	return Vector2(f * share.x, -f * share.y)


## The slip as a share of the peak's in each direction: [code](slip ratio over the peak's,
## tan(slip angle) over tan(the peak's))[/code], signed; 1 at the peak.
static func slip_share(spec: PackedFloat64Array, ratio: float, angle: float) -> Vector2:
	return Vector2(ratio / spec[CarSpec.PEAK_RATIO],
		tan(clampf(angle, -1.5, 1.5)) / tan(spec[CarSpec.PEAK_ANGLE]))


## How far the tread deflects at the peak, metres, along and across: the relaxation length times
## the peak slip in each direction. [method contact] keeps its deflection as shares of these.
static func tread_scale(spec: PackedFloat64Array) -> Vector2:
	var sigma := spec[CarSpec.RELAXATION]
	return Vector2(sigma * spec[CarSpec.PEAK_RATIO], sigma * tan(spec[CarSpec.PEAK_ANGLE]))


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
		across: float, wheel_load: float, mu: float, dt: float) -> Vector4:
	return touch(prepare(spec, deflect, along, across, wheel_load, mu, dt), tread)


## The parts of [method contact] that do not hang on the tread's speed, worked out once for a
## step: a wheel's spin is solved by trying many tread speeds against the same road.
static func prepare(spec: PackedFloat64Array, deflect: Vector2, along: float, across: float,
		wheel_load: float, mu: float, dt: float) -> PackedFloat64Array:
	var p := PackedFloat64Array()
	p.resize(_SIZE)
	var top := peak(spec, wheel_load, mu)
	p[_TOP] = top
	if top <= 0.0:
		return p
	var sigma := spec[CarSpec.RELAXATION]
	var tan_peak := tan(spec[CarSpec.PEAK_ANGLE])
	var scale := tread_scale(spec)
	var px := scale.x
	var py := scale.y
	var speed := sqrt(along * along + across * across)
	var relax := 1.0 + speed * dt / sigma
	var b := spec[CarSpec.TYRE_B]
	var shape := spec[CarSpec.TYRE_SHAPE]
	p[_ALONG] = along
	p[_DT] = dt
	p[_PX] = px
	p[_RELAX] = relax
	p[_SPEED] = maxf(speed, SLIDE_FLOOR)
	p[_DEFLECT_X] = deflect.x
	p[_DEFLECT_Y] = deflect.y
	p[_UY] = (deflect.y + across * dt / py) / relax
	p[_ACROSS_SHARE] = across / tan_peak
	p[_PEAK_RATIO] = spec[CarSpec.PEAK_RATIO]
	p[_B] = b
	p[_SHAPE] = shape
	# The tread's own damping, which stills it where rolling cannot relax it: slowly.
	var still := clampf(1.0 - speed / DAMPED_BELOW, 0.0, 1.0)
	if still > 0.0:
		var quarter := spec[CarSpec.MASS] * 0.25
		var stiff := top * b * shape
		p[_DAMP_X] = 2.0 * DAMPING * sqrt(stiff / px * quarter) * px * still / dt
		p[_DAMP_Y] = 2.0 * DAMPING * sqrt(stiff / py * quarter) * py * still / dt
	return p


## [method contact] at the tread speed [param tread] over the road [param p] that
## [method prepare] gave: [code]Vector4(along force, across force, deflection along, deflection
## across)[/code].
static func touch(p: PackedFloat64Array, tread: float) -> Vector4:
	var top := p[_TOP]
	if top <= 0.0:
		return Vector4.ZERO
	var slide := tread - p[_ALONG]
	var ux := (p[_DEFLECT_X] + slide * p[_DT] / p[_PX]) / p[_RELAX]
	var uy := p[_UY]
	var size := sqrt(ux * ux + uy * uy)
	var fx := 0.0
	var fy := 0.0
	if size > 1.0:
		ux /= size
		uy /= size
		var sx := slide / p[_PEAK_RATIO]
		var sliding := sqrt(sx * sx + p[_ACROSS_SHARE] * p[_ACROSS_SHARE]) / p[_SPEED]
		var held := top * magic(maxf(sliding, 1.0), p[_B], p[_SHAPE])
		fx = ux * held
		fy = uy * held
	elif size > 0.0:
		var held := top * magic(size, p[_B], p[_SHAPE]) / size
		fx = ux * held + (ux - p[_DEFLECT_X]) * p[_DAMP_X]
		fy = uy * held + (uy - p[_DEFLECT_Y]) * p[_DAMP_Y]
		var total := sqrt(fx * fx + fy * fy)
		if total > top:
			fx *= top / total
			fy *= top / total
	return Vector4(fx, -fy, ux, uy)


## The slots of [method prepare]'s numbers.
const _TOP := 0
const _ALONG := 1
const _DT := 2
const _PX := 3
const _RELAX := 4
const _SPEED := 5
const _DEFLECT_X := 6
const _DEFLECT_Y := 7
const _UY := 8
const _ACROSS_SHARE := 9
const _PEAK_RATIO := 10
const _B := 11
const _SHAPE := 12
const _DAMP_X := 13
const _DAMP_Y := 14
const _SIZE := 15


## How hard the tyre works, 0 at rest to 1 at its peak and more past it: the combined slip as a
## share of the peak slip. The tyre voices read it.
static func usage(spec: PackedFloat64Array, ratio: float, angle: float) -> float:
	return slip_share(spec, ratio, angle).length()


## Slip ratio of a wheel whose tread moves at [param tread] m/s over ground passing at
## [param ground] m/s; at walking pace the ground speed is floored so it stays finite.
static func slip_ratio(tread: float, ground: float) -> float:
	return (tread - ground) / maxf(absf(ground), 1.5)


## Slip angle of a contact patch moving [param along] forward and [param across] to the left of
## the wheel, radians; floored at walking pace like [method slip_ratio].
static func slip_angle(along: float, across: float) -> float:
	return atan2(across, maxf(absf(along), 1.5))
