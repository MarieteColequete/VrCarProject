@tool
class_name StopCheck
extends Check
## A stop line: the car must come to a complete stop inside the approach zone, for at least
## [member min_stop_time], before it enters the line zone. Only traffic moving along this node's
## forward axis (-Z) is checked, so the line applies to one direction.

## Where the car must stop: the stretch of road just before the line.
@export var approach_zone: TriggerZone
## Entering this zone counts as crossing the line; it starts at the line's far edge.
@export var line_zone: TriggerZone
@export var stop_fault: FaultDef = preload("res://scenarios/data/faults/stop_not_made.tres")
## Seconds the car must stay stopped.
@export var min_stop_time := 0.5


func required_exports() -> PackedStringArray:
	return ["approach_zone", "line_zone"]


func rule_script() -> Script:
	return StopRule


func rule_params(bake: Bake) -> Dictionary:
	return {approach = bake.id_of(approach_zone), line = bake.id_of(line_zone), fault = stop_fault,
		min_stop_time = min_stop_time, direction = Bake.ground_direction(-global_basis.z)}
