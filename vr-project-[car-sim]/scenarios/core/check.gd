@tool
@abstract
class_name Check
extends Node3D
## Base of every check placed in a scenario scene. A check watches the session's car and reports
## faults; it only acts while the session is running, and, when [member active_steps] is set,
## only during those steps. The session turns physics processing on when the attempt starts and
## off when it ends, so a check costs nothing outside an attempt or in the editor.
##
## A new check overrides [method _on_bound] to wire its zones with [method watch], does its
## per-tick work in [code]_physics_process[/code], reports with [method report] or
## [method report_here], and lists the exports it cannot work without in
## [method required_exports], which the editor shows as configuration warnings. Every fault
## export defaults to its fault from [code]res://scenarios/data/faults/[/code], so a scene only
## sets one to use a different fault.

## The steps during which the check acts; empty for the whole attempt.
@export var active_steps: Array[ScenarioStep] = []

var session: ExamSession


func _ready() -> void:
	set_physics_process(false)


## Called by the session once the car is spawned, before the attempt starts.
func bind(p_session: ExamSession) -> void:
	session = p_session
	_on_bound()


## Called by the session when the attempt ends, before it is scored, so a check can report a
## fault still in progress.
func finalize() -> void:
	pass


## Whether the check acts now: the attempt is running, in one of [member active_steps].
func is_live() -> bool:
	if session == null or not session.is_running():
		return false
	return active_steps.is_empty() or active_steps.has(session.current_step())


func probe() -> VehicleProbe:
	return session.probe if session else null


## Reports [param fault] at [param at]. Reports with the same [param key] from this check within
## the session's dedupe window are one fault; give distinct events, such as two different lines,
## distinct keys.
func report(fault: FaultDef, at: Vector3, key: Variant = null) -> void:
	if session:
		session.report_fault(fault, at, self, key)


## Reports [param fault] at the car's position.
func report_here(fault: FaultDef, key: Variant = null) -> void:
	var p := probe()
	if p:
		report(fault, p.global_position, key)


## Calls [param on_enter] when the session's car enters [param zone], and [param on_exit] when
## it leaves, only while the check is live. Does nothing for an unset zone, which
## [method required_exports] reports instead.
func watch(zone: TriggerZone, on_enter: Callable, on_exit := Callable()) -> void:
	if zone == null:
		return
	if on_enter.is_valid():
		zone.vehicle_entered.connect(_filtered.bind(on_enter))
	if on_exit.is_valid():
		zone.vehicle_exited.connect(_filtered.bind(on_exit))


## The exports the check cannot work without; an empty one shows as a configuration warning.
func required_exports() -> PackedStringArray:
	return PackedStringArray()


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	for property in required_exports():
		var value: Variant = get(property)
		if value == null or (value is Array and value.is_empty()):
			warnings.append("%s is not set." % property.capitalize())
	return warnings


## Called once bound to a session, with [member session] and the probe set.
func _on_bound() -> void:
	pass


func _filtered(p: VehicleProbe, handler: Callable) -> void:
	if p == probe() and is_live():
		handler.call(p)
