class_name RuleResult
extends RefCounted
## What a rule decided in one tick: its next state, the faults it reports, and whether it ends the
## current step or the attempt. Rules return one; [ExamLogic] folds it into the session.

var state: Dictionary
## Each [code][FaultDef, where, key][/code]: reports with the same key from the same rule within
## the session's dedupe window are one fault; distinct events, such as two different lines, give
## distinct keys.
var faults: Array = []
## The step this ends when it is the current one, or -1.
var complete_step := -1
## Ends the attempt as completed.
var complete := false


func _init(p_state := {}) -> void:
	state = p_state


func report(fault: FaultDef, at: Vector3, key: Variant = null) -> RuleResult:
	faults.append([fault, at, key])
	return self


## Reports [param fault] at the car's position.
func report_here(fault: FaultDef, f: RuleFrame, key: Variant = null) -> RuleResult:
	return report(fault, f.car.position if f.car else Vector3.ZERO, key)
