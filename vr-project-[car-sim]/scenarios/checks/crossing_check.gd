@tool
class_name CrossingCheck
extends Check
## A pedestrian crossing. Entering [member crossing_zone] while a pedestrian is on the crossing,
## or within [member kerb_margin] of it and still due to cross, is failing to give way. Coming to
## a stop on the crossing itself, for longer than [member grace], is a fault of its own.

@export var crossing_zone: TriggerZone
## The pedestrians who use this crossing.
@export var pedestrians: Array[ScriptedAgent] = []
## Metres around the crossing where a waiting or approaching pedestrian counts as crossing.
@export var kerb_margin := 1.5
## Seconds stopped on the crossing before it counts.
@export var grace := 1.0
@export var give_way_fault: FaultDef = preload("res://scenarios/data/faults/crossing_not_given_way.tres")
@export var stopped_on_fault: FaultDef = preload("res://scenarios/data/faults/crossing_stopped_on.tres")


func required_exports() -> PackedStringArray:
	return ["crossing_zone", "pedestrians"]


func rule_script() -> Script:
	return CrossingRule


func rule_params(bake: Bake) -> Dictionary:
	return {zone = bake.id_of(crossing_zone), pedestrians = bake.ids_of(pedestrians),
		kerb_margin = kerb_margin, grace = grace, give_way_fault = give_way_fault,
		stopped_on_fault = stopped_on_fault}
