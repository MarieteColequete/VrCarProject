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


func rule_script() -> Script:
	return LineRule


func rule_params(_bake: Bake) -> Dictionary:
	return {solid_fault = solid_fault, no_indicator_fault = no_indicator_fault,
		straddle_fault = straddle_fault, kerb_fault = kerb_fault, grace = grace,
		indicator_lead = indicator_lead, crossing_merge = crossing_merge,
		wheel_half_width = wheel_half_width}
