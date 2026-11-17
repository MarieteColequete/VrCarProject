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

var _stopped_on := Episode.new()


func required_exports() -> PackedStringArray:
	return ["crossing_zone", "pedestrians"]


func _on_bound() -> void:
	watch(crossing_zone, func(_p: VehicleProbe) -> void:
		if is_in_use():
			report_here(give_way_fault))


## Whether any of this crossing's pedestrians is on it or about to step onto it.
func is_in_use() -> bool:
	for walker in pedestrians:
		if walker and not walker.is_done() \
				and crossing_zone.contains_point(walker.global_position, kerb_margin):
			return true
	return false


func _physics_process(delta: float) -> void:
	if not is_live():
		return
	var p := probe()
	if _stopped_on.update(crossing_zone.contains(p) and p.is_stopped(), delta, grace):
		report_here(stopped_on_fault)
