class_name TransmissionUnit
extends RefCounted
## The automatic's control unit, as far as it decides from sensors: it sees the output shaft and the
## wheel speeds ([CarSignals]), never whether the tyres touch the road. It holds the gear while the
## driven wheels flare, speeding up faster than a car can ([constant FLARE]) or running well ahead
## of the undriven ones, as when they spin in the air or on ice, and for [constant HOLD] seconds
## after; the gearbox's own schedule picks the gear otherwise ([Gearbox]).

## The shaft's speeding up, m/s² at the tread, past which the driven wheels flare.
const FLARE := 12.0
## How far ahead of the undriven wheels the driven ones may run, m/s, and as a share of their speed.
const AHEAD := 3.0
const AHEAD_SHARE := 0.3
## Seconds the hold lasts once the flare is over.
const HOLD := 0.5

var _last_shaft := 0.0
var _hold_left := 0.0
var _started := false


## One step of [param dt] seconds for the car [param spec]: reads and writes [param signals].
func step(signals: CarSignals, spec: PackedFloat64Array, dt: float) -> void:
	var shaft := signals.shaft_speed
	var flaring := false
	if _started and dt > 0.0:
		flaring = absf(shaft) - absf(_last_shaft) > FLARE * dt
	_last_shaft = shaft
	_started = true
	var undriven := 0.0
	var count := 0
	for i in 4:
		if not CarSpec.driven(spec, i):
			undriven += absf(signals.wheel_speed[i])
			count += 1
	if count > 0:
		undriven /= count
		flaring = flaring or absf(shaft) - undriven > maxf(AHEAD, undriven * AHEAD_SHARE)
	_hold_left = HOLD if flaring else maxf(_hold_left - dt, 0.0)
	signals.gear_hold = _hold_left > 0.0
