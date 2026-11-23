class_name CarFeedback
extends RefCounted
## What the driver feels through the controllers, from the car's signals ([CarSignals]): a change
## beginning or going through, a refusal at the lever's end, a stall, the starter turning, ABS
## starting to work; and the bump of a tyre meeting a kerb, which is physical. Each a pulse,
## [code]Vector2(strength 0 to 1, seconds)[/code], on the step it starts. Pure state, stepped by
## the car.

## Whether a tyre met a kerb on the last step: it is heard as well as felt.
var kerb_hit := false

var _shifting := false
var _abs := false
var _on_kerb := false


## The pulses for a step of [param delta] seconds with [param signals], a tyre on a kerb when
## [param kerb].
func step(signals: CarSignals, kerb: bool, delta: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	if (signals.shifting and not _shifting) or signals.shifted:
		out.append(Vector2(0.15, 0.05))
	elif signals.shift_refused:
		out.append(Vector2(0.5, 0.15))
	_shifting = signals.shifting
	if signals.stalled:
		out.append(Vector2(1.0, 0.4))
	elif signals.start_refused:
		out.append(Vector2(0.5, 0.15))
	elif signals.engine_state == CarDynamics.EngineState.CRANKING:
		out.append(Vector2(0.15, delta))
	if signals.abs_active and not _abs:
		out.append(Vector2(0.3, 0.06))
	_abs = signals.abs_active
	kerb_hit = kerb and not _on_kerb
	if kerb_hit:
		out.append(Vector2(0.6, 0.12))
	_on_kerb = kerb
	return out
