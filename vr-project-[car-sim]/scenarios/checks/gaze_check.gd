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

@export var mirror_fault: FaultDef
@export var shoulder_fault: FaultDef
@export var require_shoulder := true
@export var window := 3.0
@export var mirror_angle := 35.0
@export var shoulder_angle := 110.0
@export var tolerance := 20.0
@export var check_move_off := false
@export var move_off_side := VehicleProbe.Indicator.LEFT
## Seconds stopped before moving off counts as a move-off.
@export var move_off_after := 2.0
## Seconds within which the wheels crossing the same line are one manoeuvre.
@export var crossing_merge := 3.0

var _times := PackedFloat32Array()
var _angles := PackedFloat32Array()
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


## Whether the driver looked [param angle] degrees to [param side] within the window.
func looked(side: VehicleProbe.Indicator, angle: float) -> bool:
	var target := angle if side == VehicleProbe.Indicator.LEFT else -angle
	var since := session.elapsed - window
	for i in _times.size():
		if _times[i] >= since and absf(_angles[i] - target) <= tolerance:
			return true
	return false


func _physics_process(_delta: float) -> void:
	if not is_live():
		return
	_record()
	var p := probe()
	if p.direction == VehicleProbe.Direction.STOPPED and p.stopped_for >= move_off_after:
		_stopped_long = true
	var index := session.scenario.marking_index()
	var before := p.previous_wheels()
	var now := p.wheels()
	for i in now.size():
		for hit in index.crossings(before[i], now[i]):
			_on_crossed(hit, p)


func _record() -> void:
	var t := session.elapsed
	_times.append(t)
	_angles.append(look_angle())
	var keep_from := 0
	while keep_from < _times.size() and _times[keep_from] < t - window - 0.5:
		keep_from += 1
	if keep_from > 0:
		_times = _times.slice(keep_from)
		_angles = _angles.slice(keep_from)


func _on_crossed(hit: Dictionary, p: VehicleProbe) -> void:
	var marking: RoadMarking = hit.marking
	if not LineCheck.LANE_LINES.has(marking.kind):
		return
	var t := session.elapsed
	var merged := _last_crossed.has(marking) and t - float(_last_crossed[marking]) < crossing_merge
	_last_crossed[marking] = t
	if merged:
		return
	var hit_normal: Vector3 = hit.normal
	var side := VehicleProbe.Indicator.LEFT \
		if hit_normal.dot(p.forward().cross(Vector3.UP)) < 0.0 else VehicleProbe.Indicator.RIGHT
	_judge(side, hit.point)


func _on_started_moving(_direction: VehicleProbe.Direction) -> void:
	if check_move_off and _stopped_long and is_live():
		_judge(move_off_side, probe().global_position)
	_stopped_long = false


func _judge(side: VehicleProbe.Indicator, at: Vector3) -> void:
	if not looked(side, mirror_angle):
		report(mirror_fault, at)
	if require_shoulder and not looked(side, shoulder_angle):
		report(shoulder_fault, at)
