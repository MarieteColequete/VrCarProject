class_name YieldCheck
extends Check
## Giving way: at a give way line, a roundabout entry, or any place where other traffic has
## priority. Entering [member conflict_zone] while a priority road user is in it, or due there in
## less than [member safe_gap] seconds, is failing to give way. Waiting stopped in
## [member approach_zone] for longer than [member hesitation_time] while every priority road user
## is at least [member clear_gap] seconds away is undue hesitation.
##
## Each road user's arrival comes from its script: [method ScriptedAgent.time_to] the point of its
## path nearest the conflict zone.

@export var conflict_zone: TriggerZone
@export var approach_zone: TriggerZone
@export var agents: Array[ScriptedAgent] = []
@export var safe_gap := 4.0
@export var clear_gap := 8.0
@export var hesitation_time := 8.0
## Metres around the conflict zone within which a road user counts as in it.
@export var zone_margin := 1.0
@export var give_way_fault: FaultDef
@export var hesitation_fault: FaultDef

var _clear_wait := 0.0
var _hesitation_reported := false
var _offsets := {}


func _on_bound() -> void:
	conflict_zone.vehicle_entered.connect(_on_entered)
	var centre := conflict_zone.global_position
	for agent in agents:
		_offsets[agent] = agent.path.curve.get_closest_offset(agent.path.to_local(centre))


## Seconds until the first priority road user reaches the conflict zone; 0 when one is in it,
## INF when none is coming.
func next_arrival() -> float:
	var soonest := INF
	for agent in agents:
		if agent.state == ScriptedAgent.State.DONE:
			continue
		if conflict_zone.contains_point(agent.global_position, zone_margin):
			return 0.0
		soonest = minf(soonest, agent.time_to(_offsets[agent]))
	return soonest


func _on_entered(p: VehicleProbe) -> void:
	if p == probe() and is_live() and next_arrival() < safe_gap:
		report(give_way_fault, p.global_position)


func _physics_process(delta: float) -> void:
	if not is_live() or approach_zone == null:
		return
	var p := probe()
	if approach_zone.contains(p) and p.is_stopped() and next_arrival() >= clear_gap:
		_clear_wait += delta
		if _clear_wait > hesitation_time and not _hesitation_reported:
			_hesitation_reported = true
			report(hesitation_fault, p.global_position)
	else:
		_clear_wait = 0.0
		_hesitation_reported = false
