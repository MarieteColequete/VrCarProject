@tool
class_name SpeedLimitCheck
extends Check
## A speed limit over a zone. An overspeed episode starts when the car exceeds the limit and ends
## when it slows below it, leaves the zone, or the attempt ends. An episode longer than
## [member grace] is one fault, serious when the highest excess reached [member serious_excess]
## of the limit, minor otherwise.

@export var zone: TriggerZone
## The limit in km/h, as signs show it.
@export var limit_kmh := 50.0
## Seconds over the limit before it counts.
@export var grace := 1.0
## Fraction of the limit above it that makes the fault serious (0.2 is 20 % over).
@export var serious_excess := 0.2
@export var minor_fault: FaultDef = preload("res://scenarios/data/faults/speeding_minor.tres")
@export var serious_fault: FaultDef = preload("res://scenarios/data/faults/speeding_serious.tres")


func required_exports() -> PackedStringArray:
	return ["zone"]


func rule_script() -> Script:
	return SpeedLimitRule


func rule_params(bake: Bake) -> Dictionary:
	return {zone = bake.id_of(zone), limit_kmh = limit_kmh, grace = grace,
		serious_excess = serious_excess, minor_fault = minor_fault, serious_fault = serious_fault}
