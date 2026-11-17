@tool
class_name LineCheck
extends Check
## Lines and kerbs, judged on the car's wheels against every [RoadMarking] of the scenario:
## crossing a solid line, crossing a dashed line without first indicating that way, riding on a
## line, and mounting a kerb. Stop and give way lines, zebras, bays, and no-parking lines belong
## to their own checks and are ignored here.
##
## The wheels crossing one marking within [member crossing_merge] seconds of each other are one
## crossing; riding on lines is one episode while any wheel stays on one.

@export var solid_fault: FaultDef = preload("res://scenarios/data/faults/line_solid_crossed.tres")
@export var no_indicator_fault: FaultDef = preload("res://scenarios/data/faults/no_indicator_lane_change.tres")
@export var straddle_fault: FaultDef = preload("res://scenarios/data/faults/line_straddled.tres")
@export var kerb_fault: FaultDef = preload("res://scenarios/data/faults/kerb_mounted.tres")
## Seconds a wheel may ride on a line before it counts.
@export var grace := 1.5
## Seconds the indicator must have shown the way before a dashed line is crossed.
@export var indicator_lead := 1.0
## Seconds within which the wheels crossing the same marking are one crossing.
@export var crossing_merge := 3.0
## Half the tyre's width, added to a line's half width when judging a wheel on it.
@export var wheel_half_width := 0.1

var _last_crossed := {}
var _straddle := Episode.new()


func _physics_process(delta: float) -> void:
	if not is_live():
		return
	var p := probe()
	for hit in session.wheel_crossings():
		_on_crossed(hit, p)
	if _straddle.update(_on_lane_line(p.wheels()), delta, grace):
		report_here(straddle_fault)


func _on_crossed(hit: MarkingHit, p: VehicleProbe) -> void:
	var marking := hit.marking
	var t := session.elapsed
	var merged := _last_crossed.has(marking) and t - float(_last_crossed[marking]) < crossing_merge
	_last_crossed[marking] = t
	if merged:
		return
	match marking.kind:
		RoadMarking.Kind.SOLID, RoadMarking.Kind.DOUBLE_SOLID:
			report(solid_fault, hit.point, marking)
		RoadMarking.Kind.DASHED:
			if p.indicator != VehicleProbe.Indicator.UNKNOWN \
					and p.indicator_held_for(p.side_of(hit.normal)) < indicator_lead:
				report(no_indicator_fault, hit.point, marking)
		RoadMarking.Kind.KERB:
			report(kerb_fault, hit.point, marking)


func _on_lane_line(wheels: PackedVector3Array) -> bool:
	var index := session.scenario.marking_index()
	for wheel in wheels:
		for marking in index.overlapping(wheel, wheel_half_width):
			if marking.is_lane_line():
				return true
	return false
