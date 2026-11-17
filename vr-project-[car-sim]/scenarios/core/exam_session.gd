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
var _crossings: Array[MarkingHit] = []
var _crossings_frame := -1


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
		_validate_faults(check)
	state = State.BRIEFING
	briefing_started.emit(definition)


## Starts the attempt after the briefing.
func begin() -> void:
	if state != State.BRIEFING:
		return
	state = State.RUNNING
	_set_checks_processing(true)
	started.emit()
	if not steps.is_empty():
		step_changed.emit(steps[0])


func abort() -> void:
	_finish(ScenarioResult.ABORTED)


func restart() -> void:
	restart_requested.emit()


## The goal was reached.
func complete() -> void:
	_finish(ScenarioResult.COMPLETED)


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


## Records a fault. A repeat from the same [param source] with the same [param key] within
## [member dedupe_window] is dropped; an eliminating fault ends the attempt.
func report_fault(def: FaultDef, at: Vector3, source: Object = null, key: Variant = null) -> void:
	if state != State.RUNNING:
		return
	if def == null:
		push_error("%s reported a fault with no FaultDef" % [source])
		return
	var dedupe := "%d:%s:%s" % [source.get_instance_id() if source else 0, def.id, key]
	if _last_report.has(dedupe) and elapsed - float(_last_report[dedupe]) < dedupe_window:
		return
	_last_report[dedupe] = elapsed
	var record := FaultRecord.new(def, elapsed, at)
	faults.append(record)
	fault_committed.emit(record)
	if definition.policy.is_eliminating(def):
		_finish.call_deferred(ScenarioResult.ELIMINATED)


## The road markings the car's wheels crossed this physics tick, computed once per tick and shared
## by every check that judges lines.
func wheel_crossings() -> Array[MarkingHit]:
	var frame := Engine.get_physics_frames()
	if frame != _crossings_frame:
		_crossings_frame = frame
		_crossings.clear()
		var before := probe.previous_wheels()
		var now := probe.wheels()
		var index := scenario.marking_index()
		for i in now.size():
			_crossings.append_array(index.crossings(before[i], now[i]))
	return _crossings


func _physics_process(delta: float) -> void:
	if state != State.RUNNING:
		return
	elapsed += delta
	if definition.time_limit > 0.0 and elapsed >= definition.time_limit:
		_finish(ScenarioResult.TIMEOUT)


func _finish(reason: StringName) -> void:
	if state != State.RUNNING:
		if state == State.BRIEFING and reason == ScenarioResult.ABORTED:
			state = State.FINISHED
		return
	# Still running while the checks close open episodes, so their last faults count.
	for check in _checks:
		check.finalize()
	_set_checks_processing(false)
	if reason == ScenarioResult.COMPLETED:
		steps_completed = steps.size()
	state = State.FINISHED
	result = ScenarioResult.new()
	result.reason = reason
	result.faults = faults.duplicate()
	result.duration = elapsed
	result.steps_completed = steps_completed
	result.step_count = steps.size()
	var score := definition.policy.evaluate(faults)
	result.passed = score.passed and reason == ScenarioResult.COMPLETED
	result.failing_tier = score.failing_tier
	finished.emit(result)


func _set_checks_processing(on: bool) -> void:
	for check in _checks:
		if is_instance_valid(check):
			check.set_physics_process(on)


## Warns about every fault a check may report whose tier the policy does not define, so the
## mistake shows when the scenario loads rather than when the fault is first committed.
func _validate_faults(check: Check) -> void:
	for property in check.get_property_list():
		if not property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			continue
		var value: Variant = check.get(property.name)
		if value is FaultDef and definition.policy.get_tier(value.tier) == null:
			push_warning("%s.%s: fault '%s' names tier '%s', which the policy does not define"
				% [check.name, property.name, value.id, value.tier])
