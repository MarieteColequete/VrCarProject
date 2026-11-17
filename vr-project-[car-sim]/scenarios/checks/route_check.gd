@tool
class_name RouteCheck
extends Check
## A lane the car should follow, given by a [Path3D] along the lane's centre in the direction of
## traffic. Each physics tick it projects the car onto the curve: the horizontal distance to it is
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

## The car's last lateral offset and distance along the route.
var lateral := 0.0
var progress := 0.0

var _lane := Episode.new()
var _road := Episode.new()
var _wrong := Episode.new()


func required_exports() -> PackedStringArray:
	return ["path"]


func _physics_process(delta: float) -> void:
	if not is_live():
		return
	var p := probe()
	var curve := path.curve
	var length := curve.get_baked_length()
	var local := path.to_local(p.global_position)
	progress = curve.get_closest_offset(local)
	if progress <= 0.01 or progress >= length - 0.01:
		return
	var flat := local - curve.sample_baked(progress)
	flat.y = 0.0
	lateral = flat.length()
	var tangent := path.global_basis * (curve.sample_baked(minf(progress + 0.5, length))
		- curve.sample_baked(maxf(progress - 0.5, 0.0)))
	tangent.y = 0.0
	var against := p.forward().dot(tangent.normalized()) < -0.5 and absf(p.speed) > wrong_way_speed

	if _road.update(lateral > road_offset, delta, lane_grace):
		report_here(road_fault)
	elif _lane.update(lateral > lane_offset and lateral <= road_offset, delta, lane_grace):
		report_here(lane_fault)
	if _wrong.update(against, delta, wrong_way_grace):
		report_here(wrong_way_fault)
