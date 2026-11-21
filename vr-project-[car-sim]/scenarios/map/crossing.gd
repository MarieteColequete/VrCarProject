@tool
class_name Crossing
extends Node3D
## A pedestrian crossing on the map: its [member zone], the pedestrians who use it, and the margin
## around it where a waiting or approaching pedestrian counts as crossing. Lanes list it in
## [member TrafficLane.crossings] so their traffic waits while it is in use, and a [CrossingCheck]
## in a scenario judges the player at it. The crossing is part of the map; how it is scored is the
## scenario's.

@export var zone: TriggerZone
## The pedestrians who use this crossing.
@export var pedestrians: Array[ScriptedAgent] = []
## Metres around the crossing where a waiting or approaching pedestrian counts as crossing.
@export var kerb_margin := 1.5


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	if zone == null:
		warnings.append("Set the crossing's zone: a TriggerZone over the crossing.")
	return warnings
