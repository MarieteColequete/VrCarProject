class_name Episode
extends RefCounted
## A condition judged as one event however long it lasts, such as riding on a line or stopping on
## a crossing: [method update] returns true once, when the condition first outlasts its grace
## time, and not again until the condition has ended and started anew.

## Seconds the condition has held without a break.
var time := 0.0
## Whether this episode has already been reported.
var reported := false


## Advances the episode by [param delta] while [param active] holds, and resets it otherwise.
## Returns true on the tick the condition first lasts longer than [param grace].
func update(active: bool, delta: float, grace: float) -> bool:
	if not active:
		reset()
		return false
	time += delta
	if time > grace and not reported:
		reported = true
		return true
	return false


func reset() -> void:
	time = 0.0
	reported = false
