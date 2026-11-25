class_name CrossingRule
extends RefCounted
## A pedestrian crossing: entering it while a pedestrian on it, or near it and still due to cross,
## is in the car's way or still walking toward it is failing to give way; one who has crossed the
## car's path and walks on away from it no longer is, as on the road. Stopping on it for longer
## than the grace is a fault of its own.


static func initial(_p: Dictionary) -> Dictionary:
	return {stopped_on = Vector2.ZERO}


static func step(p: Dictionary, s: Dictionary, f: RuleFrame, live: bool) -> RuleResult:
	var r := RuleResult.new(s)
	if not live:
		return r
	if f.entered(p.zone) and in_use(p, f):
		r.report_here(p.give_way_fault, f)
	var stopped_on := Episode.next(s.stopped_on, f.inside(p.zone) and f.car.stopped, f.dt, p.grace)
	if Episode.fired(s.stopped_on, stopped_on):
		r.report_here(p.stopped_on_fault, f)
	r.state = {stopped_on = stopped_on}
	return r


## Whether any of the crossing's pedestrians is on it or about to step onto it and in the car's
## way ([method in_the_way]).
static func in_use(p: Dictionary, f: RuleFrame) -> bool:
	for walker: int in p.pedestrians:
		var i := f.agent(walker)
		if i >= 0 and not f.agents.is_done(i) \
				and f.zone_has_point(p.zone, f.agents.position[i], p.kerb_margin) \
				and in_the_way(f.car.position, f.car.forward, f.car.body_width * 0.5 + p.clearance,
					f.agents.position[i], f.agents.facing[i]):
			return true
	return false


## Whether a pedestrian at [param at] walking toward [param facing] is in the way of a car at
## [param car] heading [param forward]: within [param half] metres of the middle of its path, or
## outside that band and walking toward it. One outside it and walking away has crossed it. One
## not walking across the road is counted in the way.
static func in_the_way(car: Vector3, forward: Vector3, half: float, at: Vector3,
		facing: Vector3) -> bool:
	var right := Vector3(-forward.z, 0.0, forward.x).normalized()
	var off := (at - car).dot(right)
	if absf(off) <= half:
		return true
	var across := facing.dot(right)
	if absf(across) < 0.2:
		return true
	return signf(across) != signf(off)
