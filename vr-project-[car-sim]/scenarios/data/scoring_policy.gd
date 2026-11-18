class_name ScoringPolicy
extends Resource
## Severity tiers and pass thresholds. A country's exam is one policy file; nothing else in the
## scenario system knows the rules of a particular exam.

@export var tiers: Array[FaultTier] = []


func get_tier(id: StringName) -> FaultTier:
	for tier in tiers:
		if tier.id == id:
			return tier
	return null


func is_eliminating(fault: FaultDef) -> bool:
	var tier := get_tier(fault.tier)
	return tier != null and tier.eliminating


## Scores a list of [FaultRecord]s. Returns [code]{passed: bool, failing_tier: StringName}[/code];
## the failing tier is the first, in policy order, whose limit was exceeded, or empty on a pass.
## A fault whose tier the policy does not define fails the attempt, so a misconfigured scenario
## cannot pass silently.
func evaluate(faults: Array[FaultRecord]) -> Dictionary:
	var counts := {}
	for fault in faults:
		var tier_id := fault.def.tier
		if get_tier(tier_id) == null:
			push_error("Fault '%s' names unknown tier '%s'" % [fault.def.id, tier_id])
			return {passed = false, failing_tier = tier_id}
		counts[tier_id] = counts.get(tier_id, 0) + 1
	for tier in tiers:
		var count: int = counts.get(tier.id, 0)
		if tier.eliminating and count > 0:
			return {passed = false, failing_tier = tier.id}
		if tier.max_allowed >= 0 and count > tier.max_allowed:
			return {passed = false, failing_tier = tier.id}
	return {passed = true, failing_tier = &""}
