class_name ExamSession
extends Node
## One attempt at a scenario: it binds the scenario's checks to the car, collects their faults,
## ends the attempt, and scores it. The UI connects to its signals and calls [method begin],
## [method abort], and [method restart]; it never reaches into the checks.

signal briefing_started(definition: ScenarioDefinition)
signal started
signal fault_committed(fault: FaultRecord)
signal finished(result: ScenarioResult)
## Emitted by [method restart]; the [ExamRunner] rebuilds the scenario.
signal restart_requested

enum State { IDLE, BRIEFING, RUNNING, FINISHED }

var state := State.IDLE
var definition: ScenarioDefinition
var probe: VehicleProbe
var faults: Array[FaultRecord] = []
var elapsed := 0.0
var result: ScenarioResult

var _checks: Array[Check] = []


## Binds a spawned scenario and its car, then shows the briefing.
func setup(scenario: Scenario, p_probe: VehicleProbe) -> void:
	definition = scenario.definition
	probe = p_probe
	faults.clear()
	elapsed = 0.0
	result = null
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


func abort() -> void:
	_finish(&"aborted")


func restart() -> void:
	restart_requested.emit()


## The goal was reached.
func complete() -> void:
	_finish(&"completed")


func is_running() -> bool:
	return state == State.RUNNING


func report_fault(def: FaultDef, at: Vector3) -> void:
	if state != State.RUNNING:
		return
	if def == null:
		push_error("A check reported a fault with no FaultDef")
		return
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
	state = State.FINISHED
	result = ScenarioResult.new()
	result.reason = reason
	result.faults = faults.duplicate()
	result.duration = elapsed
	var score := definition.policy.evaluate(faults)
	result.passed = score.passed and reason == &"completed"
	result.failing_tier = score.failing_tier
	finished.emit(result)
