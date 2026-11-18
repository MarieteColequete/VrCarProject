class_name SpeedLimitRule
extends RefCounted
## A speed limit over a zone. An overspeed episode starts when the car exceeds the limit and ends
## when it slows below it, leaves the zone, or the attempt ends; one longer than the grace is one
## fault, serious when the peak reached the serious excess over the limit.


static func initial(_p: Dictionary) -> Dictionary:
	return {over_for = 0.0, peak = 0.0, peak_at = Vector3.ZERO}


static func step(p: Dictionary, s: Dictionary, f: RuleFrame, live: bool) -> RuleResult:
	var r := RuleResult.new(s)
	if not live:
		return r
	if f.exited(p.zone):
		r = _end(p, r.state, r, live)
	if not f.inside(p.zone):
		return r
	var kmh := f.car.speed_kmh()
	if kmh > p.limit_kmh:
		var n: Dictionary = r.state.duplicate()
		n.over_for += f.dt
		if kmh > n.peak:
			n.peak = kmh
			n.peak_at = f.car.position
		r.state = n
		return r
	return _end(p, r.state, r, live)


static func finish(p: Dictionary, s: Dictionary, _f: RuleFrame, live: bool) -> RuleResult:
	return _end(p, s, RuleResult.new(s), live)


static func _end(p: Dictionary, s: Dictionary, r: RuleResult, live: bool) -> RuleResult:
	if s.over_for > p.grace and live:
		var serious: bool = s.peak >= p.limit_kmh * (1.0 + p.serious_excess)
		r.report(p.serious_fault if serious else p.minor_fault, s.peak_at)
	r.state = initial(p)
	return r
