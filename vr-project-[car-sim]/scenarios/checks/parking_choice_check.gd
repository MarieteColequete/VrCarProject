class_name ParkingChoiceCheck
extends Check
## Whether the car is parked somewhere allowed. When the car settles (stopped with the handbrake
## on, or stopped for [member settle_time]) it is judged once: inside a [NoParkingZone] or with a
## corner within [member line_distance] of a no-parking line is illegal; in a reserved bay, or in
## one marked occupied, is a fault of its own. Limit it with [member Check.active_steps] to the
## steps where the driver is choosing a place, so waiting in traffic is never read as parking.

@export var settle_time := 5.0
## Distance, in metres, from a no-parking line within which a corner counts as parked on it.
@export var line_distance := 1.0
@export var illegal_fault: FaultDef
@export var reserved_fault: FaultDef
@export var occupied_fault: FaultDef

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
	var at := p.global_position
	if _in_no_parking(p):
		report(illegal_fault, at)
		return
	var bay := _bay_under(p)
	if bay and bay.reserved:
		report(reserved_fault, at)
	elif bay and bay.occupied:
		report(occupied_fault, at)


func _in_no_parking(p: VehicleProbe) -> bool:
	for node in get_tree().get_nodes_in_group(&"no_parking_zone"):
		if session.scenario.is_ancestor_of(node) and (node as NoParkingZone).contains(p):
			return true
	var index := session.scenario.marking_index()
	for corner in p.corners():
		for marking in index.overlapping(corner, line_distance):
			if marking.kind == RoadMarking.Kind.NO_PARKING:
				return true
	return false


func _bay_under(p: VehicleProbe) -> ParkingBay:
	for node in get_tree().get_nodes_in_group(&"parking_bay"):
		var bay := node as ParkingBay
		if session.scenario.is_ancestor_of(bay) and bay.contains(p.global_position):
			return bay
	return null
