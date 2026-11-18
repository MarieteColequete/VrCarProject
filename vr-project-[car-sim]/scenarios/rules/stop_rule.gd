class_name StopRule
extends RefCounted
## A stop line: the car must stop completely in the approach zone, for the minimum stop time,
## before it enters the line zone. Only traffic moving along the line's direction is checked.


static func initial(_p: Dictionary) -> Dictionary:
	return {stop = Vector2.ZERO, satisfied = false, judged = false}


static func step(p: Dictionary, s: Dictionary, f: RuleFrame, live: bool) -> RuleResult:
	var n := s.duplicate()
	var r := RuleResult.new(n)
	if not live:
		return r
	var car := f.car
	if f.entered(p.approach) and car.travels_along(p.direction):
		n.stop = Vector2.ZERO
		n.satisfied = false
		n.judged = false
	if f.entered(p.line) and not n.judged and car.travels_along(p.direction):
		n.judged = true
		if not n.satisfied:
			r.report_here(p.fault, f)
	if not n.satisfied:
		var next := Episode.next(n.stop, f.inside(p.approach) and car.stopped, f.dt, p.min_stop_time)
		if Episode.fired(n.stop, next):
			n.satisfied = true
		n.stop = next
	return r


static func finish(_p: Dictionary, s: Dictionary, _f: RuleFrame, _live: bool) -> RuleResult:
	return RuleResult.new(s)
