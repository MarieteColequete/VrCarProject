class_name ExamSession
extends Node
## One attempt at a scenario: it binds the scenario's checks to the car, collects their faults,
## ends the attempt, and scores it. The UI connects to its signals and calls [method begin],
## [method abort], and [method restart]; it never reaches into the checks.

signal briefing_started(definition: ScenarioDefinition)
signal started
signal fault_committed(fault: FaultRecord)
## Emitted when the attempt starts and each time it moves on to the next step.
signal step_changed(step: ScenarioStep)
signal finished(result: ScenarioResult)
## Emitted by [method restart]; the [ExamRunner] rebuilds the scenario.
signal restart_requested

enum State { IDLE, BRIEFING, RUNNING, FINISHED }

var state := State.IDLE
var definition: ScenarioDefinition
var scenario: Scenario
var probe: VehicleProbe
var faults: Array[FaultRecord] = []
var elapsed := 0.0
var result: ScenarioResult
## The scenario's steps, in order, and how many are done.
var steps: Array[ScenarioStep] = []
var steps_completed := 0
## A check reporting the same fault again within this many seconds is ignored, so one event does
## not become several records.
@export var dedupe_window := 1.0

var _checks: Array[Check] = []
var _last_report := {}


## Binds a spawned scenario and its car, then shows the briefing.
func setup(p_scenario: Scenario, p_probe: VehicleProbe) -> void:
	scenario = p_scenario
	definition = scenario.definition
	probe = p_probe
	faults.clear()
	elapsed = 0.0
	result = null
	steps = scenario.get_steps()
	steps_completed = 0
	_last_report.clear()
	_checks = scenario.get_checks()
	for check in _checks:
		check.bind(self)
	state = State.BRIEFING
	briefing_started.emit(definition)


## Starts the attempt after the briefing.
func begin() -> void:
	if state != State.BRIEFING:
		return
	state = State.RUNNING
	started.emit()
	if not steps.is_empty():
		step_changed.emit(steps[0])


func abort() -> void:
	_finish(&"aborted")


func restart() -> void:
	restart_requested.emit()


## The goal was reached.
func complete() -> void:
	_finish(&"completed")


## The current step, or null when the scenario has no steps or they are all done.
func current_step() -> ScenarioStep:
	return steps[steps_completed] if steps_completed < steps.size() else null


## Ends [param step] when it is the current one; the last step completes the attempt.
func complete_step(step: ScenarioStep) -> void:
	if state != State.RUNNING or step != current_step():
		return
	if steps_completed + 1 >= steps.size():
		complete()
		return
	steps_completed += 1
	step_changed.emit(current_step())


func is_running() -> bool:
	return state == State.RUNNING


func report_fault(def: FaultDef, at: Vector3, source: Object = null) -> void:
	if state != State.RUNNING:
		return
	if def == null:
		push_error("A check reported a fault with no FaultDef")
		return
	var key := "%d:%s" % [source.get_instance_id() if source else 0, def.id]
	if _last_report.has(key) and elapsed - float(_last_report[key]) < dedupe_window:
		return
	_last_report[key] = elapsed
	var record := FaultRecord.new(def, elapsed, at)
	faults.append(record)
	fault_committed.emit(record)
	if definition.policy.is_eliminating(def):
		_finish.call_deferred(&"eliminated")


func _physics_process(delta: float) -> void:
	if state != State.RUNNING:
		return
	elapsed += delta
	if definition.time_limit > 0.0 and elapsed >= definition.time_limit:
		_finish(&"timeout")


func _finish(reason: StringName) -> void:
	if state != State.RUNNING:
		if state == State.BRIEFING and reason == &"aborted":
			state = State.FINISHED
		return
	# Still running while the checks close open episodes, so their last faults count.
	for check in _checks:
		check.finalize()
	if reason == &"completed":
		steps_completed = steps.size()
	state = State.FINISHED
	result = ScenarioResult.new()
	result.reason = reason
	result.faults = faults.duplicate()
	result.duration = elapsed
	result.steps_completed = steps_completed
	result.step_count = steps.size()
	var score := definition.policy.evaluate(faults)
	result.passed = score.passed and reason == &"completed"
	result.failing_tier = score.failing_tier
	finished.emit(result)
