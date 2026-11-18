@tool
class_name JunctionCheck
extends Check
## Turning at a junction: which way the car leaves, and whether it signalled that way. The
## indicator is read as the car leaves [member approach_zone], the point where the turn is
## committed, or, with [member judge_on_exit], as it reaches the exit, the rule at roundabouts
## where the way out is signalled on leaving. Leaving by a [JunctionExit] that needs a side the
## indicator had not shown for [member indicator_lead] seconds by then is turning without
## indicating, and leaving by an exit the route does not allow is a wrong turn. The exits are
## this check's children.

## The approach to the junction; leaving it commits the turn.
@export var approach_zone: TriggerZone
## Reads the indicator at the exit instead of on leaving the approach.
@export var judge_on_exit := false
## Seconds the indicator must have shown the way.
@export var indicator_lead := 1.0
@export var indicator_fault: FaultDef = preload("res://scenarios/data/faults/no_indicator_turn.tres")
@export var wrong_turn_fault: FaultDef = preload("res://scenarios/data/faults/wrong_turn.tres")


func required_exports() -> PackedStringArray:
	return PackedStringArray() if judge_on_exit else PackedStringArray(["approach_zone"])


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := super()
	if not get_children().any(func(c: Node) -> bool: return c is JunctionExit):
		warnings.append("Add the junction's ways out as JunctionExit children.")
	return warnings


func rule_script() -> Script:
	return JunctionRule


func rule_params(bake: Bake) -> Dictionary:
	var exits: Array[Dictionary] = []
	for child in get_children():
		if child is JunctionExit:
			exits.append({zone = bake.id_of(child), side = child.side, allowed = child.allowed})
	return {approach = bake.id_of(approach_zone), judge_on_exit = judge_on_exit,
		indicator_lead = indicator_lead, indicator_fault = indicator_fault,
		wrong_turn_fault = wrong_turn_fault, exits = exits}
