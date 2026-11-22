class_name MirrorAdjust
extends RefCounted
## Setting the mirrors with the controls, as a car's mirror switch does: [constant ACTION] picks
## the interior mirror, then the left, then the right, then none, and while one is picked the look
## controls tilt it instead of turning the head. It is for a car standing still: it lets go once
## the car moves faster than [constant MOVING], or after [constant IDLE] seconds untouched. Pure
## state: the car feeds it the controls and tilts the mirror it picks.

const ACTION := &"mirror_adjust"
## How fast a full push of the look controls tilts the mirror, radians per second.
const RATE := 0.35
## How long the switch waits untouched before letting go, seconds.
const IDLE := 6.0
## The speed above which the switch lets go, metres per second (5 km/h).
const MOVING := 5.0 / 3.6

## The mirror picked, an index into the car's mirrors, or -1 for none.
var picked := -1

var _idle := 0.0


## Picks the next of [param count] mirrors, after the last none; the mirror now picked.
func cycle(count: int) -> int:
	picked = picked + 1 if picked + 1 < count else -1
	_idle = 0.0
	return picked


## Whether a mirror is picked.
func active() -> bool:
	return picked >= 0


## A step of [param delta] seconds with the look stick at [param look] (x to the right, y down,
## as [method Input.get_vector] gives it), [param touched] true when the controls moved otherwise
## (the mouse), and the car at [param speed]: the picked mirror's tilt change from the stick. Lets
## go when the car moves or the controls rest too long; [method active] then says so.
func step(delta: float, look: Vector2, speed: float, touched := false) -> Vector2:
	if picked < 0:
		return Vector2.ZERO
	if absf(speed) > MOVING:
		picked = -1
		return Vector2.ZERO
	if look == Vector2.ZERO and not touched:
		_idle += delta
		if _idle >= IDLE:
			picked = -1
		return Vector2.ZERO
	_idle = 0.0
	return Vector2(look.x, -look.y) * RATE * delta
