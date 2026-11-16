class_name LineCheck
extends Check
## Lines and kerbs, judged on the car's wheels against every [RoadMarking] of the scenario:
## crossing a solid line, crossing a dashed line without first indicating that way, riding on a
## line, and mounting a kerb. Stop and give way lines, zebras, bays, and no-parking lines belong
## to their own checks and are ignored here.
##
## The wheels crossing one marking within [member crossing_merge] seconds of each other are one
## crossing; riding on lines is one episode while any wheel stays on one.

@export var solid_fault: FaultDef
@export var no_indicator_fault: FaultDef
@export var straddle_fault: FaultDef
@export var kerb_fault: FaultDef
## Seconds a wheel may ride on a line before it counts.
@export var straddle_grace := 1.5
## Seconds the indicator must have shown the way before a dashed line is crossed.
@export var indicator_lead := 1.0
## Seconds within which the wheels crossing the same marking are one crossing.
@export var crossing_merge := 3.0
## Half the tyre's width, added to a line's half width when judging a wheel on it.
@export var wheel_half_width := 0.1

const LANE_LINES: Array[RoadMarking.Kind] = [
	RoadMarking.Kind.SOLID, RoadMarking.Kind.DASHED, RoadMarking.Kind.DOUBLE_SOLID]

var _index: MarkingIndex
var _last_crossed := {}
var _straddle_time := 0.0
var _straddle_reported := false


func _on_bound() -> void:
	_index = session.scenario.marking_index()
	_last_crossed.clear()
	_straddle_time = 0.0
	_straddle_reported = false


func _physics_process(delta: float) -> void:
	if not is_live():
		return
	var p := probe()
	var before := p.previous_wheels()
	var now := p.wheels()
	for i in now.size():
		for hit in _index.crossings(before[i], now[i]):
			_on_crossed(hit, p)
	_update_straddle(now, delta, p)


func _on_crossed(hit: Dictionary, p: VehicleProbe) -> void:
	var marking: RoadMarking = hit.marking
	var t := session.elapsed
	var merged := _last_crossed.has(marking) and t - float(_last_crossed[marking]) < crossing_merge
	_last_crossed[marking] = t
	if merged:
		return
	match marking.kind:
		RoadMarking.Kind.SOLID, RoadMarking.Kind.DOUBLE_SOLID:
			report(solid_fault, hit.point)
		RoadMarking.Kind.DASHED:
			if p.indicator == VehicleProbe.Indicator.UNKNOWN:
				return
			var car_right := p.forward().cross(Vector3.UP)
			var hit_normal: Vector3 = hit.normal
			var side := VehicleProbe.Indicator.LEFT if hit_normal.dot(car_right) < 0.0 \
				else VehicleProbe.Indicator.RIGHT
			if p.indicator_held_for(side) < indicator_lead:
				report(no_indicator_fault, hit.point)
		RoadMarking.Kind.KERB:
			report(kerb_fault, hit.point)


func _update_straddle(wheels: PackedVector3Array, delta: float, p: VehicleProbe) -> void:
	var on_line := false
	for wheel in wheels:
		for marking in _index.overlapping(wheel, wheel_half_width):
			if LANE_LINES.has(marking.kind):
				on_line = true
	if not on_line:
		_straddle_time = 0.0
		_straddle_reported = false
		return
	_straddle_time += delta
	if _straddle_time > straddle_grace and not _straddle_reported:
		_straddle_reported = true
		report(straddle_fault, p.global_position)
