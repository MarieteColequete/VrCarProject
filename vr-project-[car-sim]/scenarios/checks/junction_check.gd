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

var _held := {}
var _judged := false


func required_exports() -> PackedStringArray:
	return PackedStringArray() if judge_on_exit else PackedStringArray(["approach_zone"])


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := super()
	if not get_children().any(func(c: Node) -> bool: return c is JunctionExit):
		warnings.append("Add the junction's ways out as JunctionExit children.")
	return warnings


func _on_bound() -> void:
	if not judge_on_exit:
		watch(approach_zone, Callable(), _on_committed)
	for child in get_children():
		if child is JunctionExit:
			watch(child, _on_exit.bind(child))


func _on_committed(p: VehicleProbe) -> void:
	_judged = false
	_read_indicator(p)


func _read_indicator(p: VehicleProbe) -> void:
	for side in [VehicleProbe.Indicator.LEFT, VehicleProbe.Indicator.RIGHT]:
		_held[side] = p.indicator_held_for(side)


func _on_exit(p: VehicleProbe, exit: JunctionExit) -> void:
	if _judged:
		return
	if judge_on_exit:
		_read_indicator(p)
	elif _held.is_empty():
		return
	_judged = true
	if not exit.allowed:
		report_here(wrong_turn_fault)
	if exit.side != VehicleProbe.Indicator.OFF and p.indicator != VehicleProbe.Indicator.UNKNOWN \
			and float(_held.get(exit.side, 0.0)) < indicator_lead:
		report_here(indicator_fault)
