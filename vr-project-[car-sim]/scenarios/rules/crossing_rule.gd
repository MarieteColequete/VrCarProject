class_name CrossingRule
extends RefCounted
## A pedestrian crossing: entering it while a pedestrian is on it, or near it and still due to
## cross, is failing to give way; stopping on it for longer than the grace is a fault of its own.


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


static func finish(_p: Dictionary, s: Dictionary, _f: RuleFrame, _live: bool) -> RuleResult:
	return RuleResult.new(s)


## Whether any of the crossing's pedestrians is on it or about to step onto it.
static func in_use(p: Dictionary, f: RuleFrame) -> bool:
	for walker in p.pedestrians:
		var a := f.agent(walker)
		if a and not a.is_done() and f.zone_has_point(p.zone, a.position(), p.kerb_margin):
			return true
	return false
