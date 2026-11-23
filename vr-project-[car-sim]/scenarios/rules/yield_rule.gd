class_name YieldRule
extends RefCounted
## Giving way: entering the conflict zone while a priority road user is in it, or due there within
## the safe gap, is failing to give way; waiting stopped in the approach for longer than the grace
## while every priority road user is at least the clear gap away is undue hesitation.


static func initial(_p: Dictionary) -> Dictionary:
	return {hesitation = Vector2.ZERO}


static func step(p: Dictionary, s: Dictionary, f: RuleFrame, live: bool) -> RuleResult:
	var r := RuleResult.new(s)
	if not live:
		return r
	if f.entered(p.conflict) and next_arrival(p, f) < p.safe_gap:
		r.report_here(p.give_way_fault, f)
	if p.approach == 0:
		return r
	var waiting: bool = f.inside(p.approach) and f.car.stopped and next_arrival(p, f) >= p.clear_gap
	var hesitation := Episode.next(s.hesitation, waiting, f.dt, p.grace)
	if Episode.fired(s.hesitation, hesitation):
		r.report_here(p.hesitation_fault, f)
	r.state = {hesitation = hesitation}
	return r


## Seconds until the first priority road user reaches the conflict zone; 0 when one is in it, INF
## when none is coming.
static func next_arrival(p: Dictionary, f: RuleFrame) -> float:
	var soonest := INF
	var centre: Vector3 = (f.zone_value(p.conflict, &"transform") as Transform3D).origin
	for id: int in p.agents:
		var i := f.agent(id)
		if i < 0 or f.agents.is_done(i):
			continue
		if f.zone_has_point(p.conflict, f.agents.position[i], p.zone_margin):
			return 0.0
		soonest = minf(soonest, f.agents.time_to_point(i, centre, f.lanes))
	return soonest
