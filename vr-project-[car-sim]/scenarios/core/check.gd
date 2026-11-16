@abstract
class_name Check
extends Node3D
## Base of every check placed in a scenario scene. A check watches the session's car and reports
## faults; it only acts while the session is running, and, when [member active_steps] is set,
## only during those steps.

## The steps during which the check acts; empty for the whole attempt.
@export var active_steps: Array[ScenarioStep] = []

var session: ExamSession


## Called by the session once the car is spawned, before the attempt starts.
func bind(p_session: ExamSession) -> void:
	session = p_session
	_on_bound()


## Called by the session when the attempt ends, before it is scored, so a check can report a
## fault still in progress.
func finalize() -> void:
	pass


func is_live() -> bool:
	if session == null or not session.is_running():
		return false
	return active_steps.is_empty() or active_steps.has(session.current_step())


func probe() -> VehicleProbe:
	return session.probe if session else null


func report(fault: FaultDef, at: Vector3) -> void:
	if session:
		session.report_fault(fault, at, self)


func _on_bound() -> void:
	pass
