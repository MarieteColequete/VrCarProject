@tool
class_name YieldCheck
extends Check
## Giving way: at a give way line, a roundabout entry, or any place where other traffic has
## priority. Entering [member conflict_zone] while a priority road user is in it, or due there in
## less than [member safe_gap] seconds, is failing to give way. Waiting stopped in
## [member approach_zone] for longer than [member grace] while every priority road user is at
## least [member clear_gap] seconds away is undue hesitation.
##
## Each road user's arrival comes from its script: [method ScriptedAgent.time_to_point] the
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

var _hesitation := Episode.new()


func required_exports() -> PackedStringArray:
	return ["conflict_zone", "agents"]


func _on_bound() -> void:
	watch(conflict_zone, func(_p: VehicleProbe) -> void:
		if next_arrival() < safe_gap:
			report_here(give_way_fault))


## Seconds until the first priority road user reaches the conflict zone; 0 when one is in it,
## INF when none is coming.
func next_arrival() -> float:
	var soonest := INF
	var centre := conflict_zone.global_position
	for agent in agents:
		if agent == null or agent.is_done():
			continue
		if conflict_zone.contains_point(agent.global_position, zone_margin):
			return 0.0
		soonest = minf(soonest, agent.time_to_point(centre))
	return soonest


func _physics_process(delta: float) -> void:
	if not is_live() or approach_zone == null:
		return
	var p := probe()
	var waiting := approach_zone.contains(p) and p.is_stopped() and next_arrival() >= clear_gap
	if _hesitation.update(waiting, delta, grace):
		report_here(hesitation_fault)
