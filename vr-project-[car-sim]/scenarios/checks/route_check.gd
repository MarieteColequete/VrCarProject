@tool
class_name RouteCheck
extends Check
## A lane the car should follow, given by a [Path3D] along the lane's centre in the direction of
## traffic. Each tick the rule projects the car onto the curve: the horizontal distance to it is
## the lateral offset, and the curve's direction there gives wrong-way driving. It checks only
## while the car is alongside the curve, not beyond either end.
##
## Each condition is an [Episode]: one fault when it lasts longer than its grace time, and none
## again until the car is back within bounds.

@export var path: Path3D
## Lateral offset of the car's centre, in metres, beyond which it has left its lane.
@export var lane_offset := 1.2
## Lateral offset beyond which it has left the road.
@export var road_offset := 3.5
## Seconds out of lane before it counts.
@export var lane_grace := 0.75
## Seconds driving against the lane before it counts.
@export var wrong_way_grace := 1.0
## Speed, metres per second, above which wrong-way driving is judged.
@export var wrong_way_speed := 1.0
@export var lane_fault: FaultDef = preload("res://scenarios/data/faults/lane_drift.tres")
@export var road_fault: FaultDef = preload("res://scenarios/data/faults/off_route.tres")
@export var wrong_way_fault: FaultDef = preload("res://scenarios/data/faults/wrong_way.tres")


func required_exports() -> PackedStringArray:
	return ["path"]


func rule_script() -> Script:
	return RouteRule


func rule_params(bake: Bake) -> Dictionary:
	return {path = bake.lane_of(path), lane_offset = lane_offset, road_offset = road_offset,
		lane_grace = lane_grace, wrong_way_grace = wrong_way_grace,
		wrong_way_speed = wrong_way_speed, lane_fault = lane_fault, road_fault = road_fault,
		wrong_way_fault = wrong_way_fault}
