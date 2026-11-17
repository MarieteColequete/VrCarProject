class_name JunctionCheck
extends Check
## Turning at a junction: which way the car leaves, and whether it signalled that way. The
## indicator is read as the car leaves [member approach_zone], the point where the turn is
## committed, or, with [member judge_on_exit], as it reaches the exit, the rule at roundabouts
## where the way out is signalled on leaving. Leaving by a [JunctionExit] that needs a side the
## indicator had not shown for [member indicator_lead] seconds by then is turning without
## indicating, and leaving by an exit the route does not allow is a wrong turn.

@export var approach_zone: TriggerZone
@export var judge_on_exit := false
@export var indicator_lead := 1.0
@export var indicator_fault: FaultDef
@export var wrong_turn_fault: FaultDef

var _held := {}
var _judged := false


func _on_bound() -> void:
	if approach_zone:
		approach_zone.vehicle_exited.connect(_on_committed)
	for child in get_children():
		if child is JunctionExit:
			child.vehicle_entered.connect(_on_exit.bind(child))


func _on_committed(p: VehicleProbe) -> void:
	if p != probe() or judge_on_exit:
		return
	_judged = false
	_read_indicator(p)


func _read_indicator(p: VehicleProbe) -> void:
	for side in [VehicleProbe.Indicator.LEFT, VehicleProbe.Indicator.RIGHT]:
		_held[side] = p.indicator_held_for(side)


func _on_exit(p: VehicleProbe, exit: JunctionExit) -> void:
	if p != probe() or not is_live() or _judged:
		return
	if judge_on_exit:
		_read_indicator(p)
	elif _held.is_empty():
		return
	_judged = true
	if not exit.allowed:
		report(wrong_turn_fault, p.global_position)
	if exit.side != VehicleProbe.Indicator.OFF and p.indicator != VehicleProbe.Indicator.UNKNOWN \
			and float(_held.get(exit.side, 0.0)) < indicator_lead:
		report(indicator_fault, p.global_position)
