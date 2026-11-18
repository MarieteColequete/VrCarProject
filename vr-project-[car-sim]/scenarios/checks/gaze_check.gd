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


func rule_script() -> Script:
	return GazeRule


func rule_params(_bake: Bake) -> Dictionary:
	return {mirror_fault = mirror_fault, shoulder_fault = shoulder_fault,
		require_shoulder = require_shoulder, window = window, mirror_angle = mirror_angle,
		shoulder_angle = shoulder_angle, tolerance = tolerance, check_move_off = check_move_off,
		move_off_side = move_off_side, move_off_after = move_off_after,
		crossing_merge = crossing_merge}
