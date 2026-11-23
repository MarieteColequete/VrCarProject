class_name HoldTap
extends RefCounted
## A control that does one thing held and another tapped, as the gamepad's shift_down and the VR
## stick pulled down do: held [member hold] seconds it is held, once; let go sooner it was a tap.
## Pure state, stepped by its owner.

## Seconds it is held for before it counts as held.
var hold := DriverInput.PARK_HOLD
## Whether it is down now.
var down := false

var _for := 0.0


## Pressed: the hold starts counting.
func press() -> void:
	down = true
	_for = 0.0


## Let go: whether it was a tap, let go before it counted as held.
func release() -> bool:
	if not down:
		return false
	down = false
	return _for < hold


## Steps it [param delta] seconds while it is down: true the one step it comes to count as held.
func advance(delta: float) -> bool:
	if not down:
		return false
	var before := _for
	_for += delta
	return before < hold and _for >= hold
