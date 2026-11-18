class_name Episode
extends RefCounted
## A condition judged as one event however long it lasts, such as riding on a line or stopping on
## a crossing, as a pure function of values: an episode is [code]Vector2(time, reported)[/code],
## [method next] returns the next one, and [method fired] tells the tick it first outlasts its
## grace time; it fires again only once the condition has ended and started anew.


## The episode after [param delta] seconds: it grows while [param active] holds, and resets when
## it does not.
static func next(e: Vector2, active: bool, delta: float, grace: float) -> Vector2:
	if not active:
		return Vector2.ZERO
	var t := e.x + delta
	return Vector2(t, 1.0 if t > grace or e.y > 0.0 else 0.0)


## Whether the episode fired between [param before] and [param after].
static func fired(before: Vector2, after: Vector2) -> bool:
	return after.y > 0.0 and before.y == 0.0
