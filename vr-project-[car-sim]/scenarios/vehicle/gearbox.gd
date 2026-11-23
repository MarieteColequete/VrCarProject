class_name Gearbox
extends RefCounted
## A car's gearbox and its lever. The automatic has a P-R-N-D lever the driver moves one notch at a
## time ([method request]); in D it picks the forward gear itself ([method step]) from how fast the
## driven wheels turn, with hysteresis, so it never hunts. The manual steps through R, N and the
## forward gears. Neither moves on its own between reverse and forward: only the driver does, at
## any speed; a move against the car's motion is the engine's to suffer ([CarDynamics] stalls it).
## Gears are 1 and up forward, -1 reverse, 0 neutral (and park). Plain fields, no nodes.

enum Selector { PARK, REVERSE, NEUTRAL, DRIVE }

## Seconds in a gear before the automatic changes again, but for a kick-down.
const HOLD := 0.8
## Below this speed, m/s, the automatic is in first, whatever it held.
const CRAWL := 1.0
## Revolutions above the change-down point a change up must land at, so it is not undone.
const UP_MARGIN := 300.0
## The pedal past which the automatic kicks down, and the seconds it must stay there: the detent at
## the end of the pedal's travel, pressed through, not brushed on the way.
const KICK_PEDAL := 0.95
const KICK_HOLD := 0.25

var spec: PackedFloat64Array
## Whether the driver changes gear by hand.
var manual := false
var selector := Selector.PARK
var gear := 0
## Seconds left of a change between forward gears, with no drive.
var shifting := 0.0
## Seconds in the current gear.
var held_for := 0.0
## Seconds the pedal has been past [constant KICK_PEDAL].
var floored_for := 0.0


func _init(p_spec: PackedFloat64Array, p_manual := false) -> void:
	spec = p_spec
	set_manual(p_manual)


## Sets the gearbox to the manual or the automatic, starting in neutral or in park.
func set_manual(value: bool) -> void:
	manual = value
	selector = Selector.NEUTRAL if manual else Selector.PARK
	gear = 0
	shifting = 0.0
	held_for = 0.0


## The engine's revolutions per minute in [param in_gear] with the driven wheels' tread moving at
## [param wheel_speed] m/s, the clutch closed; not clamped.
func rpm_in(in_gear: int, wheel_speed: float) -> float:
	return absf(wheel_speed / spec[CarSpec.WHEEL_RADIUS] * Powertrain.ratio(spec, in_gear)) \
		* 60.0 / TAU


## Moves the lever one notch ([param step] +1 toward D, or up a gear; -1 back), with the driven
## wheels at [param wheel_speed] m/s. Returns false, moving nothing, only when the lever is at its
## end. Nothing is locked out: a move against the car's motion, or a change down past the
## redline, goes through, and the engine pays for it.
func request(step: int, wheel_speed: float) -> bool:
	if step == 0:
		return false
	if manual:
		return _request_gear(clampi(gear + signi(step), -1, Powertrain.gear_count(spec)))
	var next: int = clampi(selector + signi(step), Selector.PARK, Selector.DRIVE)
	if next == selector:
		return false
	_set_selector(next, wheel_speed)
	return true


## Puts the lever straight at [param to], as a test or a spawn does, with no lockouts.
func select(to: Selector, wheel_speed := 0.0) -> void:
	if manual:
		var gears := {Selector.REVERSE: -1, Selector.DRIVE: _gear_for(wheel_speed)}
		_engage(gears.get(to, 0))
		selector = to if to != Selector.PARK else Selector.NEUTRAL
		return
	_set_selector(to, wheel_speed)


## One step of [param dt] seconds: the change in hand goes through, and in D the automatic picks
## the gear for the driven wheels' [param wheel_speed] m/s and the [param throttle]; with
## [param grounded] false (the transmission unit sees the driven wheels flare, [TransmissionUnit])
## it holds the gear.
func step(dt: float, throttle: float, wheel_speed: float, grounded := true) -> void:
	shifting = maxf(shifting - dt, 0.0)
	floored_for = floored_for + dt if throttle > KICK_PEDAL else 0.0
	if manual or selector != Selector.DRIVE:
		held_for += dt
		return
	if not grounded:
		# The driven wheels flaring: their spin says nothing of the car's speed, so the gear holds,
		# and its time in gear waits for them to grip.
		return
	held_for += dt
	if wheel_speed < CRAWL:
		if gear != 1:
			_engage(1)
		return
	var t := clampf(throttle, 0.0, 1.0)
	var up := lerpf(spec[CarSpec.UP_GENTLE], spec[CarSpec.UP_FULL], t * t)
	var now := rpm_in(gear, wheel_speed)
	if gear < Powertrain.gear_count(spec) and now > up and held_for >= HOLD \
			and rpm_in(gear + 1, wheel_speed) > spec[CarSpec.DOWN_RPM] + UP_MARGIN:
		_engage(gear + 1)
		return
	if gear <= 1:
		return
	var lower := rpm_in(gear - 1, wheel_speed)
	var kick := floored_for >= KICK_HOLD and lower < spec[CarSpec.UP_FULL] * 0.85 \
		and held_for >= HOLD * 0.4
	var lugging := now < spec[CarSpec.DOWN_RPM] and lower < up * 0.85 and held_for >= HOLD
	if kick or lugging:
		_engage(gear - 1)


## The gear as the cluster shows it: P, R, N, or the forward gear.
func letter() -> String:
	if not manual and selector == Selector.PARK:
		return "P"
	if gear < 0:
		return "R"
	if gear == 0:
		return "N"
	return str(gear)


func _request_gear(next: int) -> bool:
	if next == gear:
		return false
	_engage(next)
	selector = Selector.REVERSE if next < 0 else (Selector.NEUTRAL if next == 0 \
		else Selector.DRIVE)
	return true


func _set_selector(to: Selector, wheel_speed: float) -> void:
	selector = to
	match to:
		Selector.REVERSE:
			_engage(-1)
		Selector.DRIVE:
			_engage(_gear_for(wheel_speed))
		_:
			_engage(0)


## The forward gear to engage at [param wheel_speed]: the lowest that keeps the engine well below
## the change-up point at full throttle.
func _gear_for(wheel_speed: float) -> int:
	var top := Powertrain.gear_count(spec)
	for g in range(1, top + 1):
		if rpm_in(g, maxf(wheel_speed, 0.0)) <= spec[CarSpec.UP_FULL] * 0.8:
			return g
	return top


func _engage(next: int) -> void:
	if next == gear:
		return
	if gear > 0 and next > 0:
		shifting = spec[CarSpec.SHIFT_TIME]
	gear = next
	held_for = 0.0
