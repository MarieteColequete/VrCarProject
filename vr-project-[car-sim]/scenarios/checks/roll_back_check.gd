@tool
class_name RollBackCheck
extends Check
## A hill start: once the car has stopped inside [member zone], it must not roll back more than
## [member max_roll] metres against this node's forward axis (-Z, up the hill) before it moves on.
## Each stop is judged on its own.

## Where the car may stop on the slope.
@export var zone: TriggerZone
@export var fault: FaultDef = preload("res://scenarios/data/faults/rolled_back.tres")
## Metres the car may roll back after stopping before it is a fault.
@export var max_roll := 0.5


func required_exports() -> PackedStringArray:
	return ["zone"]


func rule_script() -> Script:
	return RollBackRule


func rule_params(bake: Bake) -> Dictionary:
	return {zone = bake.id_of(zone), fault = fault, max_roll = max_roll,
		direction = Geo.ground_direction(-global_basis.z)}
