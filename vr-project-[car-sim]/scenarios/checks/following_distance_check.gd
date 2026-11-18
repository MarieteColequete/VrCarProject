@tool
class_name FollowingDistanceCheck
extends Check
## Following distance: the time gap to a road user ahead in the same lane, the clear distance
## between the car's front and its rear divided by the car's speed, must stay at least
## [member min_gap] seconds. Staying closer for longer than [member grace] is one fault per
## episode. Only [member agents] are considered, and only above [member min_speed], so queuing in
## slow traffic is not judged.

## The road users whose distance is judged.
@export var agents: Array[ScriptedAgent] = []
@export var following_fault: FaultDef = preload("res://scenarios/data/faults/following_too_close.tres")
## The smallest time gap allowed, seconds.
@export var min_gap := 2.0
## Seconds closer than the gap before it counts.
@export var grace := 2.0
## Metres off the car's line within which a road user counts as in the same lane.
@export var lane_half_width := 1.5
## Speed, metres per second, below which the gap is not judged.
@export var min_speed := 3.0


func required_exports() -> PackedStringArray:
	return ["agents"]


func rule_script() -> Script:
	return FollowingDistanceRule


func rule_params(bake: Bake) -> Dictionary:
	return {agents = bake.ids_of(agents), fault = following_fault, min_gap = min_gap,
		grace = grace, lane_half_width = lane_half_width, min_speed = min_speed}
