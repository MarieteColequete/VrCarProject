class_name WheelGrab
extends RefCounted
## Steering with the hands on the wheel, in VR. A hand gripping within [constant REACH] of the
## steering wheel's rim takes hold of it there; while held, the wheel turns as the holding hands
## move round the rim (the average of the two when both hold it), and it centres itself once let go.
## Pure state and geometry: the driver's view feeds it the hands and reads the steering, so tests
## can drive it with made-up hands.

## How far from the rim a gripping hand takes hold, metres.
const REACH := 0.1
## How fast the wheel centres itself once let go, radians per second.
const CENTRING := 4.0

## The wheel's turn, radians, anticlockwise as the driver sees it (to the left) positive.
var angle := 0.0
## The most the wheel turns either way, radians.
var lock := deg_to_rad(150.0)
## Each hand's hold: its angle round the rim last step, or null while it does not hold the wheel.
var holds: Array = [null, null]


## Whether any hand holds the wheel.
func held() -> bool:
	return holds[0] != null or holds[1] != null


## The steering the wheel gives, -1 (full right) to 1 (full left).
func steer() -> float:
	return clampf(angle / lock, -1.0, 1.0)


## A step of [param delta] seconds with the wheel at [param wheel] (its origin the rim's centre,
## +Z the column pointing at the driver) of rim [param radius], and the hands at
## [param hands] (two world positions), gripping as [param grips] says. [param start] is the
## steering to take hold at when no hand held the wheel, so taking hold does not jerk it.
func step(delta: float, wheel: Transform3D, radius: float, hands: Array, grips: Array,
		start: float) -> void:
	var was_held := held()
	var turned := 0.0
	var holding := 0
	for i in 2:
		var at: Vector3 = hands[i]
		if not grips[i]:
			holds[i] = null
			continue
		var here := rim_angle(wheel, at)
		if holds[i] == null:
			if rim_distance(wheel, radius, at) > REACH:
				continue
			if not was_held and holding == 0:
				angle = start * lock
			holds[i] = here
			continue
		turned += wrapf(here - float(holds[i]), -PI, PI)
		holding += 1
		holds[i] = here
	if holding > 0:
		angle = clampf(angle + turned / holding, -lock, lock)
	elif not held():
		angle = move_toward(angle, 0.0, CENTRING * delta)


## How far [param at] is from the rim of the wheel at [param wheel] of [param radius].
static func rim_distance(wheel: Transform3D, radius: float, at: Vector3) -> float:
	var local := wheel.affine_inverse() * at
	var across := Vector2(local.x, local.y).length()
	return Vector2(across - radius, local.z).length()


## Where round the rim [param at] is, radians, anticlockwise as the driver sees it from 12
## o'clock.
static func rim_angle(wheel: Transform3D, at: Vector3) -> float:
	var local := wheel.affine_inverse() * at
	# The driver looks along -Z at the wheel: +X is to the right, +Y up.
	return atan2(-local.x, local.y)


## The point on the rim nearest [param at], in world space: where a holding hand is drawn.
static func on_rim(wheel: Transform3D, radius: float, at: Vector3) -> Vector3:
	var local := wheel.affine_inverse() * at
	var across := Vector2(local.x, local.y)
	if across.length() < 0.0001:
		across = Vector2(0.0, 1.0)
	across = across.normalized() * radius
	return wheel * Vector3(across.x, across.y, 0.0)
