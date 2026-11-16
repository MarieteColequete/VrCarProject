class_name CrossingCheck
extends Check
## A pedestrian crossing. Entering [member crossing_zone] while a pedestrian is on the crossing,
## or within [member kerb_margin] of it and still due to cross, is failing to give way. Coming to
## a stop on the crossing itself, for longer than [member stop_grace], is a fault of its own.

@export var crossing_zone: TriggerZone
## The pedestrians who use this crossing.
@export var pedestrians: Array[ScriptedAgent] = []
## Metres around the crossing where a waiting or approaching pedestrian counts as crossing.
@export var kerb_margin := 1.5
@export var stop_grace := 1.0
@export var give_way_fault: FaultDef
@export var stopped_on_fault: FaultDef

var _stopped_on_for := 0.0
var _stopped_on_reported := false


func _on_bound() -> void:
	crossing_zone.vehicle_entered.connect(_on_entered)


## Whether any of this crossing's pedestrians is on it or about to step onto it.
func is_in_use() -> bool:
	for walker in pedestrians:
		if walker.state != ScriptedAgent.State.DONE \
				and crossing_zone.contains_point(walker.global_position, kerb_margin):
			return true
	return false


func _on_entered(p: VehicleProbe) -> void:
	if p == probe() and is_live() and is_in_use():
		report(give_way_fault, p.global_position)


func _physics_process(delta: float) -> void:
	if not is_live():
		return
	var p := probe()
	if crossing_zone.contains(p) and p.is_stopped():
		_stopped_on_for += delta
		if _stopped_on_for > stop_grace and not _stopped_on_reported:
			_stopped_on_reported = true
			report(stopped_on_fault, p.global_position)
	else:
		_stopped_on_for = 0.0
		_stopped_on_reported = false
