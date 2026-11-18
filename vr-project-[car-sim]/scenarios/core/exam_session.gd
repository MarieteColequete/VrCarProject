class_name ExamSession
extends Node
## One attempt at a scenario, as the UI sees it: signals for the briefing, the start, each step,
## each fault, and the end, and commands to begin, abort, and restart. The attempt itself lives in
## the [World] and runs in [ExamLogic]; this node turns the world's events into signals and the
## UI's commands into the world's reducers, so a UI never reaches into the simulation.

signal briefing_started(definition: ScenarioDefinition)
signal started
signal fault_committed(fault: FaultRecord)
## Emitted when the attempt starts and each time it moves on to the next step.
signal step_changed(step: ScenarioStep)
signal finished(result: ScenarioResult)
## Emitted by [method restart]; the [ExamRunner] rebuilds the scenario.
signal restart_requested

enum State { IDLE, BRIEFING, RUNNING, FINISHED }

var state: State:
	get:
		return _value(&"state", State.IDLE)
var definition: ScenarioDefinition:
	get:
		return _value(&"definition", null)
## Seconds since the attempt started running.
var elapsed: float:
	get:
		return _value(&"elapsed", 0.0)
var faults: Array:
	get:
		return _value(&"faults", [])
var result: ScenarioResult:
	get:
		return _value(&"result", null)
var steps_completed: int:
	get:
		return _value(&"steps_completed", 0)
## The scenario's steps, in order.
var steps: Array[ScenarioStep]:
	get:
		var w := _world()
		var out: Array[ScenarioStep] = []
		if w and w.resources.has(Schema.STEPS):
			out.assign(w.resources[Schema.STEPS])
		return out

var _runner: WorldRunner


## Follows the attempt of [param runner]'s world.
func attach(runner: WorldRunner) -> void:
	if _runner and is_instance_valid(_runner) and _runner.events_emitted.is_connected(_on_events):
		_runner.events_emitted.disconnect(_on_events)
	_runner = runner
	_runner.events_emitted.connect(_on_events)


## Shows the briefing of the baked attempt.
func setup() -> void:
	if state == State.BRIEFING:
		briefing_started.emit(definition)


## Starts the attempt after the briefing.
func begin() -> void:
	if _world():
		_runner.apply_now(ExamLogic.begin(_world()))


func abort() -> void:
	if _world():
		_runner.apply_now(ExamLogic.abort(_world()))


## Records a fault from outside the scenario's rules, such as an instructor's call.
func report_fault(fault: FaultDef, at: Vector3) -> void:
	if _world():
		_runner.apply_now(ExamLogic.report(_world(), fault, at))


func restart() -> void:
	if _world():
		_runner.apply_now(ExamLogic.restart(_world()))


func is_running() -> bool:
	return state == State.RUNNING


## The current step, or null when the scenario has no steps or they are all done.
func current_step() -> ScenarioStep:
	var all := steps
	return all[steps_completed] if steps_completed < all.size() else null


func _on_events(events: Array[WorldEvent]) -> void:
	for event in events:
		match event.kind:
			&"started":
				started.emit()
			&"step_changed":
				var all := steps
				if event.data.step < all.size():
					step_changed.emit(all[event.data.step])
			&"fault":
				fault_committed.emit(event.data.record)
			&"finished":
				finished.emit(event.data.result)
			&"restart":
				restart_requested.emit()


func _world() -> World:
	return _runner.world if _runner and is_instance_valid(_runner) else null


func _value(column: StringName, fallback: Variant) -> Variant:
	var w := _world()
	if w == null:
		return fallback
	var id := Schema.single(w, Schema.SESSION)
	return w.get_value(Schema.SESSION, id, column) if id else fallback
