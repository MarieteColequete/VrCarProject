class_name FollowingDistanceCheck
extends Check
## Following distance: the time gap to a road user ahead in the same lane, the clear distance
## between the car's front and its rear divided by the car's speed, must stay at least
## [member min_gap] seconds. Staying closer for longer than [member grace] is one fault per
## episode. Only [member agents] are considered, and only above [member min_speed], so queuing in
## slow traffic is not judged.

@export var agents: Array[ScriptedAgent] = []
@export var fault: FaultDef
@export var min_gap := 2.0
@export var grace := 2.0
## Metres off the car's line within which a road user counts as in the same lane.
@export var lane_half_width := 1.5
@export var min_speed := 3.0

## The current time gap to the nearest road user ahead, INF when there is none.
var time_gap := INF

var _close_for := 0.0
var _reported := false


func _physics_process(delta: float) -> void:
	if not is_live():
		return
	var p := probe()
	time_gap = _time_gap(p)
	if time_gap < min_gap:
		_close_for += delta
		if _close_for > grace and not _reported:
			_reported = true
			report(fault, p.global_position)
	else:
		_close_for = 0.0
		_reported = false


func _time_gap(p: VehicleProbe) -> float:
	if p.speed < min_speed:
		return INF
	var fwd := p.forward()
	var right := fwd.cross(Vector3.UP)
	var nearest := INF
	for agent in agents:
		var offset := agent.global_position - p.global_position
		offset.y = 0.0
		var ahead := offset.dot(fwd)
		if ahead <= 0.0 or absf(offset.dot(right)) > lane_half_width:
			continue
		var clear := ahead - p.body_length * 0.5 - agent.body_size.z * 0.5
		nearest = minf(nearest, maxf(clear, 0.0) / p.speed)
	return nearest
