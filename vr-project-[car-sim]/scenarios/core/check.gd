@abstract
class_name Check
extends Node3D
## Base of every check placed in a scenario scene. A check watches the session's car and reports
## faults; it only acts while the session is running.

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
	return session != null and session.is_running()


func probe() -> VehicleProbe:
	return session.probe if session else null


func report(fault: FaultDef, at: Vector3) -> void:
	if session:
		session.report_fault(fault, at)


func _on_bound() -> void:
	pass
