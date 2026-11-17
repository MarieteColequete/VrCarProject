@tool
class_name ParkingChoiceCheck
extends Check
## Whether the car is parked somewhere allowed. When the car settles (stopped with the handbrake
## on, or stopped for [member settle_time]) it is judged once: inside a [NoParkingZone] or with a
## corner within [member line_distance] of a no-parking line is illegal; in a reserved bay, or in
## one marked occupied, is a fault of its own. Limit it with [member Check.active_steps] to the
## steps where the driver is choosing a place, so waiting in traffic is never read as parking.

## Seconds stopped, without the handbrake, after which the car counts as parked; longer than
## [member ParkingCheck.settle_time], so a pause while manoeuvring is not judged as a choice.
@export var settle_time := 5.0
## Distance, in metres, from a no-parking line within which a corner counts as parked on it.
@export var line_distance := 1.0
@export var illegal_fault: FaultDef = preload("res://scenarios/data/faults/parking_illegal.tres")
@export var reserved_fault: FaultDef = preload("res://scenarios/data/faults/parking_reserved.tres")
@export var occupied_fault: FaultDef = preload("res://scenarios/data/faults/parking_occupied.tres")

var _judged := false


func _physics_process(_delta: float) -> void:
	if not is_live():
		return
	var p := probe()
	if p.direction != VehicleProbe.Direction.STOPPED:
		_judged = false
		return
	if _judged or not p.is_settled(settle_time):
		return
	_judged = true
	if _in_no_parking(p):
		report_here(illegal_fault)
		return
	var bay := session.scenario.bay_at(p.global_position)
	if bay and bay.reserved:
		report_here(reserved_fault)
	elif bay and bay.occupied:
		report_here(occupied_fault)


func _in_no_parking(p: VehicleProbe) -> bool:
	for zone in session.scenario.no_parking_zones():
		if zone.contains(p):
			return true
	var index := session.scenario.marking_index()
	for corner in p.corners():
		for marking in index.overlapping(corner, line_distance):
			if marking.kind == RoadMarking.Kind.NO_PARKING:
				return true
	return false
