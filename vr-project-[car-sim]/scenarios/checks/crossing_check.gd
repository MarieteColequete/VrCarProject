@tool
class_name CrossingCheck
extends Check
## Judges the player at a [Crossing] of the map. Entering its zone while a pedestrian on the
## crossing, or within its kerb margin and still due to cross, is in the car's path (within
## [member clearance] of its sides) or walking toward it is failing to give way; one who has
## crossed the car's path and walks on away is not. Coming to a stop on the crossing itself, for
## longer than [member grace], is a fault of its own.

@export var crossing: Crossing
## Metres beside the car's sides within which a pedestrian still counts as in its way.
@export var clearance := 1.0
## Seconds stopped on the crossing before it counts.
@export var grace := 1.0
@export var give_way_fault: FaultDef = preload("res://scenarios/data/faults/crossing_not_given_way.tres")
@export var stopped_on_fault: FaultDef = preload("res://scenarios/data/faults/crossing_stopped_on.tres")


func required_exports() -> PackedStringArray:
	return ["crossing"]


func rule_script() -> Script:
	return CrossingRule


func rule_params(bake: Bake) -> Dictionary:
	return {zone = bake.id_of(crossing.zone), pedestrians = bake.ids_of(crossing.pedestrians),
		kerb_margin = crossing.kerb_margin, clearance = clearance, grace = grace,
		give_way_fault = give_way_fault,
		stopped_on_fault = stopped_on_fault}
