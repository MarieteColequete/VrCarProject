class_name PipelinedSystem
extends RefCounted
## A system whose work runs across a tick boundary, on worker threads: the [WorldRunner] calls
## [method begin] once a tick's changes are applied, with the world as it now stands, and
## [method finish] at the start of the next tick, before anything else, and applies the [Delta]
## it returns. The work therefore overlaps the rest of the tick (the views, rendering, and the
## engine's own physics step), and its results land one tick later, decided from a world no one
## changed in between. Implementations copy what they need in [method begin], on the main thread,
## and touch no node and no world while working.


## Main thread: copies what the work needs from [param world] and starts it.
func begin(_world: World, _dt: float) -> void:
	pass


## Main thread: waits for the work started by [method begin], if any, and returns its result.
func finish() -> Delta:
	return null
