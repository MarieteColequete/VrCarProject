class_name Damped
extends RefCounted
## A critically damped spring: a value that follows its target as fast as [param omega] allows
## without overshooting, as a gauge's needle or a car body's lean does. Pure; the caller keeps the
## value and its velocity.


## The value and its velocity, as [code]Vector2(value, velocity)[/code], after following
## [param target] for [param delta] seconds from [param value] moving at [param velocity].
static func step(value: float, velocity: float, target: float, omega: float,
		delta: float) -> Vector2:
	# The exact solution over the step, so a long step stays stable.
	var x := value - target
	var e := exp(-omega * delta)
	var k := (velocity + omega * x) * delta
	var next := target + (x + k) * e
	var next_velocity := (velocity - omega * k) * e
	return Vector2(next, next_velocity)
