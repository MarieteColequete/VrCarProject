class_name JunctionCheck
extends Check
## Turning at a junction: which way the car leaves, and whether it signalled that way. The
## indicator is read as the car leaves [member approach_zone], the point where the turn is
## committed; leaving by a [JunctionExit] that needs a side the indicator had not shown for
## [member indicator_lead] seconds then is turning without indicating, and leaving by an exit the
## route does not allow is a wrong turn.

@export var approach_zone: TriggerZone
@export var indicator_lead := 1.0
@export var indicator_fault: FaultDef
@export var wrong_turn_fault: FaultDef

var _held := {}
var _judged := false


func _on_bound() -> void:
	approach_zone.vehicle_exited.connect(_on_committed)
	for child in get_children():
		if child is JunctionExit:
			child.vehicle_entered.connect(_on_exit.bind(child))


func _on_committed(p: VehicleProbe) -> void:
	if p != probe():
		return
	_judged = false
	for side in [VehicleProbe.Indicator.LEFT, VehicleProbe.Indicator.RIGHT]:
		_held[side] = p.indicator_held_for(side)


func _on_exit(p: VehicleProbe, exit: JunctionExit) -> void:
	if p != probe() or not is_live() or _judged or _held.is_empty():
		return
	_judged = true
	if not exit.allowed:
		report(wrong_turn_fault, p.global_position)
	if exit.side != VehicleProbe.Indicator.OFF and p.indicator != VehicleProbe.Indicator.UNKNOWN \
			and float(_held.get(exit.side, 0.0)) < indicator_lead:
		report(indicator_fault, p.global_position)
