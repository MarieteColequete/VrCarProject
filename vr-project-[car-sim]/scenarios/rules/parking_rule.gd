class_name ParkingRule
extends RefCounted
## How well the car is parked. When it settles with its centre in one of the judged bays, the
## manoeuvre is judged once: overhang, facing, direction changes, and time, counted from when the
## rule became live. Parking well in a free bay completes the rule's step.


static func initial(_p: Dictionary) -> Dictionary:
	return {baseline = -1, started = 0.0, judged = false}


static func step(p: Dictionary, s: Dictionary, f: RuleFrame, live: bool) -> RuleResult:
	var n := s.duplicate()
	var r := RuleResult.new(n)
	if not live:
		n.baseline = -1
		return r
	var car := f.car
	if n.baseline < 0:
		n.baseline = car.direction_changes
		n.started = f.elapsed
	if car.direction != VehicleProbe.Direction.STOPPED:
		n.judged = false
		return r
	if n.judged or not car.is_settled(p.settle_time):
		return r
	n.judged = true
	var bay := f.bay_at(car.position, p.bays)
	if bay.is_empty():
		return r
	var over := Geo.overhang(bay.transform, bay.size, car.corners)
	if over > p.overhang_margin:
		r.report_here(p.overhang_serious_fault, f)
	elif over > 0.0:
		r.report_here(p.overhang_minor_fault, f)
	if facing_error(bay, car.forward) > p.facing_tolerance:
		r.report_here(p.misaligned_fault, f)
	if car.direction_changes - n.baseline > p.max_direction_changes:
		r.report_here(p.manoeuvres_fault, f)
	if p.time_limit > 0.0 and f.elapsed - n.started > p.time_limit:
		r.report_here(p.too_slow_fault, f)
	if p.step >= 0 and not bay.reserved and not bay.occupied:
		r.complete_step = p.step
	return r


static func finish(_p: Dictionary, s: Dictionary, _f: RuleFrame, _live: bool) -> RuleResult:
	return RuleResult.new(s)


## Degrees between [param forward] and the way [param bay] requires a car to face.
static func facing_error(bay: Dictionary, forward: Vector3) -> float:
	var angles := Geo.facing_angles(-(bay.transform as Transform3D).basis.z, forward)
	match bay.facing:
		ParkingBay.Facing.NOSE_IN:
			return angles.x
		ParkingBay.Facing.REVERSED:
			return angles.y
	return minf(angles.x, angles.y)
