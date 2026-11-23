class_name Suspension
extends RefCounted
## The player's car's four corners: each spring and damper, the anti-roll bars between them, and
## the bump stops at the end of their travel. Given how far each wheel is pushed up into its
## travel this step, it gives the load each one carries, which the ground pushes back along its
## own normal: a spring pushes the road, never the car along it. Node free: it keeps
## its own state from step to step and reads nothing but its arguments.

## How much stiffer the bump stop is than the spring.
const BUMP_STOP := 20.0

## Each corner's compression in the last step, metres; 0 for a wheel in the air.
var compression := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])

var _settled := false


## Each corner's load, newtons, for the car [param spec] over a step of [param dt] seconds, each
## wheel pushed [param squeezed] metres into its travel where [param grounded]; a corner in the
## air carries none. The first step after [method reset] has no damping, since nothing moved yet.
func loads(spec: PackedFloat64Array, squeezed: PackedFloat64Array, grounded: PackedByteArray,
		dt: float) -> PackedFloat64Array:
	var out := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var travel := spec[CarSpec.TRAVEL]
	for i in 4:
		if not grounded[i]:
			continue
		var rate := (squeezed[i] - compression[i]) / dt if _settled else 0.0
		var spring := CarDynamics.corner_load(spec, squeezed[i], rate, squeezed[i ^ 1])
		if squeezed[i] > travel:
			spring += (squeezed[i] - travel) * spec[CarSpec.SPRING_RATE] * BUMP_STOP
		out[i] = spring
	for i in 4:
		compression[i] = squeezed[i] if grounded[i] else 0.0
	_settled = true
	return out


## Forgets the last step's motion, for a car placed by hand.
func reset() -> void:
	_settled = false
