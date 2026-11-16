class_name ScenarioResult
extends RefCounted
## The outcome of one attempt at a scenario, handed to the UI by [signal ExamSession.finished].

## How the session ended: [code]completed[/code] (goal reached), [code]eliminated[/code] (an
## eliminating fault), [code]timeout[/code], or [code]aborted[/code].
var reason: StringName
var passed := false
## The tier that failed the attempt, empty on a pass.
var failing_tier: StringName
var faults: Array[FaultRecord] = []
## Seconds the session ran.
var duration := 0.0


func count_tier(tier: StringName) -> int:
	var n := 0
	for fault in faults:
		if fault.def.tier == tier:
			n += 1
	return n


func has_fault(id: StringName) -> bool:
	for fault in faults:
		if fault.def.id == id:
			return true
	return false


func summary() -> String:
	var lines := PackedStringArray()
	lines.append("%s (%s) in %.1f s, %d fault(s)" % [
		"PASS" if passed else "FAIL", reason, duration, faults.size()])
	for fault in faults:
		lines.append("  - %s" % fault)
	return "\n".join(lines)
