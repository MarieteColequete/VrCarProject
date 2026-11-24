class_name Steering
extends RefCounted
## The player's car's steering: the steering wheel, the rack, and the front wheels on it. It is
## geometry only: turning the steering wheel turns each front wheel to its road angle, and that is
## all. It pushes nothing, reads no speed and no aid changes it; the car turns only as its tyres
## grip the road while it moves. The rack's travel gives [constant CarSpec.STEER_LOCK] at full
## turn, and its arms follow Ackermann's geometry: the inner wheel turns further, so every wheel
## rolls round one centre on the line of the rear axle. Node free: it keeps
## its own state from step to step and reads nothing but its arguments.

## How far the steering wheel turns at full lock either way, radians: 900 degrees lock to lock, two
## and a half turns, as a road car's and the common sim wheel's default (Logitech's 900, most
## others 900 to 1080), so a wheel at its default turns the car's 1:1.
const WHEEL_TURN := deg_to_rad(450.0)

## The steering wheel's turn, -1 (full right) to 1 (full left).
var turn := 0.0
## Each wheel's road angle, radians, left positive, in [CarDynamics]' order; the rears are 0.
var angles := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
## The rack's angle, radians, left positive: the angle of a wheel midway between the fronts, as
## the steering angle sensor reads it.
var rack := 0.0


## Turns the steering wheel to [param p_turn] for the car [param spec].
func steer(spec: PackedFloat64Array, p_turn: float) -> void:
	turn = clampf(p_turn, -1.0, 1.0)
	rack = turn * spec[CarSpec.STEER_LOCK]
	var both := ackermann(spec, rack)
	angles[CarDynamics.FL] = both.x
	angles[CarDynamics.FR] = both.y
	angles[CarDynamics.RL] = 0.0
	angles[CarDynamics.RR] = 0.0


## The front wheels' angles, [code](left, right)[/code] radians, for the rack at [param middle]:
## each points square to the line from it to the turn's centre on the rear axle's line.
static func ackermann(spec: PackedFloat64Array, middle: float) -> Vector2:
	if absf(middle) < 0.000001:
		return Vector2.ZERO
	var base := spec[CarSpec.WHEELBASE]
	var half := spec[CarSpec.TRACK] * 0.5
	# The turn's centre, from the car's middle line, left positive.
	var centre := base / tan(middle)
	return Vector2(atan(base / (centre - half)), atan(base / (centre + half)))
