class_name Damped
extends RefCounted
## Values that follow a target smoothly. [method step] is a critically damped spring: it follows
## as fast as [param omega] allows without overshooting, as a gauge's needle or a car body's lean
## does; the caller keeps the value and its velocity. [method follow] is a simple lag, most of the
## way there in a time constant, as a temperature or a sound's level does. Pure.


## The value and its velocity, as [code]Vector2(value, velocity)[/code], after following
## [param target] for [param delta] seconds from [param value] moving at [param velocity].
## [param current] moved toward [param target] over [param delta] seconds, about two thirds of the
## way in [param tau] seconds.
static func follow(current: float, target: float, delta: float, tau: float) -> float:
	return lerpf(current, target, 1.0 - exp(-delta / tau))


static func step(value: float, velocity: float, target: float, omega: float,
		delta: float) -> Vector2:
	# The exact solution over the step, so a long step stays stable.
	var x := value - target
	var e := exp(-omega * delta)
	var k := (velocity + omega * x) * delta
	var next := target + (x + k) * e
	var next_velocity := (velocity - omega * k) * e
	return Vector2(next, next_velocity)
