class_name ScenarioResult
extends RefCounted
## The outcome of one attempt at a scenario, handed to the UI by [signal ExamSession.finished].

## The goal was reached.
const COMPLETED := &"completed"
## An eliminating fault ended the attempt.
const ELIMINATED := &"eliminated"
## The time limit ran out.
const TIMEOUT := &"timeout"
## The attempt was stopped before its end.
const ABORTED := &"aborted"

## How the session ended: [constant COMPLETED], [constant ELIMINATED], [constant TIMEOUT], or
## [constant ABORTED].
var reason: StringName
var passed := false
## The tier that failed the attempt, empty on a pass.
var failing_tier: StringName
var faults: Array[FaultRecord] = []
## Seconds the session ran.
var duration := 0.0
## How many of the scenario's steps were done, out of [member step_count].
var steps_completed := 0
var step_count := 0
## The scenario attempted.
var scenario_id: StringName
var scenario_title: String
## The policy the attempt was scored by, for the tier counts and limits.
var policy: ScoringPolicy


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


## The result as plain data, for the UI and for saving attempts.
func to_dict() -> Dictionary:
	var fault_list := []
	for fault in faults:
		fault_list.append({
			id = String(fault.def.id),
			title = fault.def.title,
			description = fault.def.description,
			tier = String(fault.def.tier),
			time = fault.time,
			position = [fault.position.x, fault.position.y, fault.position.z],
		})
	var tier_list := []
	if policy:
		for tier in policy.tiers:
			tier_list.append({
				id = String(tier.id),
				title = tier.title,
				count = count_tier(tier.id),
				max_allowed = tier.max_allowed,
				eliminating = tier.eliminating,
			})
	return {
		scenario = {id = String(scenario_id), title = scenario_title},
		tiers = tier_list,
		reason = String(reason),
		passed = passed,
		failing_tier = String(failing_tier),
		duration = duration,
		steps_completed = steps_completed,
		step_count = step_count,
		faults = fault_list,
	}


func summary() -> String:
	var lines := PackedStringArray()
	lines.append("%s (%s) in %.1f s, %d fault(s)" % [
		"PASS" if passed else "FAIL", reason, duration, faults.size()])
	for fault in faults:
		lines.append("  - %s" % fault)
	return "\n".join(lines)
