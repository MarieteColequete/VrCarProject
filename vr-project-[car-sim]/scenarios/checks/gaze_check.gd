@tool
class_name GazeCheck
extends Check
## Observation before a manoeuvre: when the car crosses a lane line (a lane change or pulling out
## to overtake), the driver must have looked at the mirror on that side, and over that shoulder
## when [member require_shoulder] is set, within the [member window] seconds before. With
## [member check_move_off], moving off after a stop needs the same looks to
## [member move_off_side]. Where the driver looks comes from [method VehicleProbe.look_direction],
## the headset in VR or the mouse and stick otherwise.
##
## Looks are measured as the angle from the car's forward direction, positive to the left; a
## mirror look is [member mirror_angle] and a shoulder look [member shoulder_angle] to that side,
## each within [member tolerance].

@export var mirror_fault: FaultDef = preload("res://scenarios/data/faults/no_mirror_check.tres")
@export var shoulder_fault: FaultDef = preload("res://scenarios/data/faults/no_shoulder_check.tres")
## Whether a shoulder look is needed as well as a mirror look.
@export var require_shoulder := true
## Seconds before the manoeuvre within which the looks count.
@export var window := 3.0
## Degrees from straight ahead of a look at a side mirror.
@export var mirror_angle := 35.0
## Degrees from straight ahead of a look over the shoulder.
@export var shoulder_angle := 110.0
## Degrees either side of a look's angle that still count as that look.
@export var tolerance := 20.0
## Judges moving off after a stop as a manoeuvre too.
@export var check_move_off := false
## The side moving off pulls out to.
@export_enum("Left:2", "Right:3") var move_off_side: int = VehicleProbe.Indicator.LEFT
## Seconds stopped before moving off counts as a move-off.
@export var move_off_after := 2.0
## Seconds within which the wheels crossing the same line are one manoeuvre.
@export var crossing_merge := 3.0

# The last session time each tracked look was seen, keyed by its signed angle.
var _last_seen := {}
var _last_crossed := {}
var _stopped_long := false


func _on_bound() -> void:
	probe().started_moving.connect(_on_started_moving)


## The driver's look as a signed angle from the car's forward direction, degrees, left positive.
func look_angle() -> float:
	var p := probe()
	var look := p.look_direction()
	look.y = 0.0
	if look.length() < 0.001:
		return 0.0
	return rad_to_deg(p.forward().signed_angle_to(look.normalized(), Vector3.UP))


## Whether the driver looked [param angle] degrees to [param side] within the window. Only the
## mirror and shoulder angles are tracked.
func looked(side: VehicleProbe.Indicator, angle: float) -> bool:
	var target := _signed(side, angle)
	return _last_seen.has(target) and session.elapsed - float(_last_seen[target]) <= window


func _physics_process(_delta: float) -> void:
	if not is_live():
		return
	_record()
	var p := probe()
	if p.direction == VehicleProbe.Direction.STOPPED and p.stopped_for >= move_off_after:
		_stopped_long = true
	for hit in session.wheel_crossings():
		_on_crossed(hit, p)


func _record() -> void:
	var angle := look_angle()
	for side in [VehicleProbe.Indicator.LEFT, VehicleProbe.Indicator.RIGHT]:
		for target_angle in [mirror_angle, shoulder_angle]:
			var target := _signed(side, target_angle)
			if absf(angle - target) <= tolerance:
				_last_seen[target] = session.elapsed


func _on_crossed(hit: MarkingHit, p: VehicleProbe) -> void:
	var marking := hit.marking
	if not marking.is_lane_line():
		return
	var t := session.elapsed
	var merged := _last_crossed.has(marking) and t - float(_last_crossed[marking]) < crossing_merge
	_last_crossed[marking] = t
	if merged:
		return
	_judge(p.side_of(hit.normal), hit.point)


func _on_started_moving(_direction: VehicleProbe.Direction) -> void:
	if check_move_off and _stopped_long and is_live():
		_judge(move_off_side, probe().global_position)
	_stopped_long = false


func _judge(side: VehicleProbe.Indicator, at: Vector3) -> void:
	if not looked(side, mirror_angle):
		report(mirror_fault, at)
	if require_shoulder and not looked(side, shoulder_angle):
		report(shoulder_fault, at)


static func _signed(side: VehicleProbe.Indicator, angle: float) -> float:
	return angle if side == VehicleProbe.Indicator.LEFT else -angle
