class_name RouteCheck
extends Check
## A lane the car should follow, given by a [Path3D] along the lane's centre in the direction of
## traffic. Each physics tick it projects the car onto the curve: the horizontal distance to it is
## the lateral offset, and the curve's direction there gives wrong-way driving. It checks only
## while the car is alongside the curve, not beyond either end.
##
## Each condition is an episode: one fault when it lasts longer than its grace time, and none
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
@export var lane_fault: FaultDef
@export var road_fault: FaultDef
@export var wrong_way_fault: FaultDef

## The car's last lateral offset and distance along the route, for debugging and the UI.
var lateral := 0.0
var progress := 0.0

var _lane := _Episode.new()
var _road := _Episode.new()
var _wrong := _Episode.new()


class _Episode:
	var time := 0.0
	var reported := false

	## Advances the episode; returns true once, when it first outlasts the grace time.
	func step(active: bool, delta: float, grace: float) -> bool:
		if not active:
			time = 0.0
			reported = false
			return false
		time += delta
		if time > grace and not reported:
			reported = true
			return true
		return false


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
	var closest := curve.sample_baked(progress)
	var flat := local - closest
	flat.y = 0.0
	lateral = flat.length()
	var tangent := curve.sample_baked(minf(progress + 0.5, length)) \
		- curve.sample_baked(maxf(progress - 0.5, 0.0))
	tangent = path.global_basis * tangent
	tangent.y = 0.0
	var against := p.forward().dot(tangent.normalized()) < -0.5 and absf(p.speed) > wrong_way_speed

	if _road.step(lateral > road_offset, delta, lane_grace):
		report(road_fault, p.global_position)
	elif _lane.step(lateral > lane_offset and lateral <= road_offset, delta, lane_grace):
		report(lane_fault, p.global_position)
	if _wrong.step(against, delta, wrong_way_grace):
		report(wrong_way_fault, p.global_position)
