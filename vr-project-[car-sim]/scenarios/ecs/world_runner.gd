class_name WorldRunner
extends Node
## The imperative shell around the [World]: the one place where the simulation meets nodes,
## input, and rendering. Each physics tick, first in the tree, it:
## [br]1. applies the results of the [PipelinedSystem]s started last tick;
## [br]2. runs the inputs, which read nodes (the player's car, the driver's view, the clock) and
##    turn them into component values;
## [br]3. runs the systems stage by stage: within a stage every system reads the same world, and
##    their deltas are applied, in the order the systems were added, before the next stage runs,
##    so a later stage sees what an earlier one decided this tick (zones see where the car is now,
##    rules see which zones it entered);
## [br]4. starts the pipelined systems on the world as it now stands;
## [br]5. publishes the tick's events through [signal events_emitted];
## [br]6. runs the views, which draw the world (meshes, lights, physics proxies).
## [br]Systems never touch nodes and views never change the world, so the simulation runs the
## same with or without anything drawn, and its outcome does not depend on the threads' timing.

## The events of one tick, in the order they were applied.
signal events_emitted(events: Array[WorldEvent])

const NODE_NAME := &"WorldRunner"

var world := World.new()
## Microseconds the last tick spent in each part, by name: [code]&"pipelined"[/code],
## [code]&"inputs"[/code], each stage's number, [code]&"begin"[/code], [code]&"events"[/code], and
## [code]&"views"[/code].
var timings := {}

var _inputs: Array[Callable] = []
# Stage number to the systems of that stage, in the order added, and the stages in order.
var _stages := {}
var _stage_order: Array = []
var _pipelined: Array[PipelinedSystem] = []
var _views: Array[Callable] = []


func _ready() -> void:
	process_physics_priority = -1000


## Adds an input: [code]func(world: World, dt: float) -> Delta[/code], run on the main thread,
## the only kind of step allowed to read nodes.
func add_input(input: Callable) -> void:
	_inputs.append(input)


## Adds a system: [code]func(world: World, dt: float) -> Delta[/code], a pure function of the
## world, to [param stage]. Stages run in ascending order; the systems of a stage run in the order
## added, all reading the world as the previous stage left it.
func add_system(system: Callable, stage := 0) -> void:
	if not _stages.has(stage):
		_stages[stage] = []
		_stage_order.append(stage)
		_stage_order.sort()
	_stages[stage].append(system)


func add_pipelined(system: PipelinedSystem) -> void:
	_pipelined.append(system)


## Adds a view: [code]func(world: World) -> void[/code], run on the main thread after the tick,
## the only kind of step allowed to write nodes and servers.
func add_view(view: Callable) -> void:
	_views.append(view)


func _physics_process(delta: float) -> void:
	step(delta)


## Runs one tick of [param dt] seconds; the physics process calls it, and tests may too.
func step(dt: float) -> void:
	var t := Time.get_ticks_usec()
	world.begin_tick(dt)
	for system in _pipelined:
		world.apply(system.finish())
	t = _lap(&"pipelined", t)
	for input in _inputs:
		world.apply(input.call(world, dt))
	t = _lap(&"inputs", t)
	for stage: int in _stage_order:
		var deltas: Array[Delta] = []
		for system: Callable in _stages[stage]:
			deltas.append(system.call(world, dt))
		for d in deltas:
			world.apply(d)
		t = _lap(stage, t)
	for system in _pipelined:
		system.begin(world, dt)
	t = _lap(&"begin", t)
	if not world.events.is_empty():
		events_emitted.emit(world.events)
	t = _lap(&"events", t)
	for view in _views:
		view.call(world)
	_lap(&"views", t)


func _lap(part: Variant, since: int) -> int:
	var now := Time.get_ticks_usec()
	timings[part] = now - since
	return now


## Applies [param delta] outside a tick, such as the result of a command from the UI, and
## publishes its events at once.
func apply_now(delta: Delta) -> void:
	var before := world.events.size()
	world.apply(delta)
	if world.events.size() > before:
		events_emitted.emit(world.events.slice(before))


## The pipelined systems, for readouts such as the HUD's.
func pipelined() -> Array[PipelinedSystem]:
	return _pipelined


## Lets work still running end; call before freeing a runner that never entered the tree.
func stop() -> void:
	for system in _pipelined:
		system.finish()


func _exit_tree() -> void:
	# Work still running may hold the world; let it end before the runner goes.
	stop()
