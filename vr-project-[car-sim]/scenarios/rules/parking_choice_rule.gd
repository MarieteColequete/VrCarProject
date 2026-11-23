class_name ParkingChoiceRule
extends RefCounted
## Whether the car is parked somewhere allowed. When it settles it is judged once: in a no-parking
## zone, or with a corner near a no-parking line, is illegal; in a reserved or occupied bay is a
## fault of its own.


static func initial(_p: Dictionary) -> Dictionary:
	return {judged = false}


static func step(p: Dictionary, s: Dictionary, f: RuleFrame, live: bool) -> RuleResult:
	var n := s.duplicate()
	var r := RuleResult.new(n)
	if not live:
		return r
	var car := f.car
	if car.direction != VehicleProbe.Direction.STOPPED:
		n.judged = false
		return r
	if n.judged or not car.is_settled(p.settle_time):
		return r
	n.judged = true
	if _in_no_parking(p, f):
		r.report_here(p.illegal_fault, f)
		return r
	var bay := f.bay_at(car.position)
	if not bay.is_empty() and bay.reserved:
		r.report_here(p.reserved_fault, f)
	elif not bay.is_empty() and bay.occupied:
		r.report_here(p.occupied_fault, f)
	return r


static func _in_no_parking(p: Dictionary, f: RuleFrame) -> bool:
	for zone in f.zones_of(&"no_parking"):
		if f.inside(zone):
			return true
	if f.markings == null:
		return false
	for corner in f.car.corners:
		for marking in f.markings.overlapping(corner, p.line_distance):
			if f.markings.kind_of(marking) == RoadMarking.Kind.NO_PARKING:
				return true
	return false
