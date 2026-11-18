@tool
class_name YieldCheck
extends Check
## Giving way: at a give way line, a roundabout entry, or any place where other traffic has
## priority. Entering [member conflict_zone] while a priority road user is in it, or due there in
## less than [member safe_gap] seconds, is failing to give way. Waiting stopped in
## [member approach_zone] for longer than [member grace] while every priority road user is at
## least [member clear_gap] seconds away is undue hesitation.
##
## Each road user's arrival comes from its script: [method AgentTable.time_to_point] the
## conflict zone, along its path or the lane it continues onto.

## Where priority traffic crosses the car's path.
@export var conflict_zone: TriggerZone
## Where the car waits to enter; empty to leave hesitation unjudged.
@export var approach_zone: TriggerZone
## The road users with priority.
@export var agents: Array[ScriptedAgent] = []
## Seconds of clear road that entering needs.
@export var safe_gap := 4.0
## Seconds of clear road in which waiting is hesitation.
@export var clear_gap := 8.0
## Seconds waiting on a clear road before it counts as hesitation.
@export var grace := 8.0
## Metres around the conflict zone within which a road user counts as in it.
@export var zone_margin := 1.0
@export var give_way_fault: FaultDef = preload("res://scenarios/data/faults/failed_to_give_way.tres")
@export var hesitation_fault: FaultDef = preload("res://scenarios/data/faults/undue_hesitation.tres")


func required_exports() -> PackedStringArray:
	return ["conflict_zone", "agents"]


func rule_script() -> Script:
	return YieldRule


func rule_params(bake: Bake) -> Dictionary:
	return {conflict = bake.id_of(conflict_zone), approach = bake.id_of(approach_zone),
		agents = bake.ids_of(agents), safe_gap = safe_gap, clear_gap = clear_gap, grace = grace,
		zone_margin = zone_margin, give_way_fault = give_way_fault,
		hesitation_fault = hesitation_fault}
