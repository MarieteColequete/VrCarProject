class_name FollowingDistanceRule
extends RefCounted
## Following distance: the time gap to a road user ahead in the same lane, the clear distance
## between the car's front and its rear over the car's speed, must stay at least the minimum gap;
## closer for longer than the grace is one fault per episode, judged only above the minimum speed.


static func initial(_p: Dictionary) -> Dictionary:
	return {time_gap = INF, close = Vector2.ZERO}


static func step(p: Dictionary, s: Dictionary, f: RuleFrame, live: bool) -> RuleResult:
	var r := RuleResult.new(s)
	if not live:
		return r
	var gap := time_gap(p, f)
	var close := Episode.next(s.close, gap < p.min_gap, f.dt, p.grace)
	if Episode.fired(s.close, close):
		r.report_here(p.fault, f)
	r.state = {time_gap = gap, close = close}
	return r


static func finish(_p: Dictionary, s: Dictionary, _f: RuleFrame, _live: bool) -> RuleResult:
	return RuleResult.new(s)


static func time_gap(p: Dictionary, f: RuleFrame) -> float:
	var car := f.car
	if car.speed < p.min_speed:
		return INF
	var fwd := car.forward
	var right := fwd.cross(Vector3.UP)
	var nearest := INF
	for id: int in p.agents:
		var i := f.agent(id)
		if i < 0:
			continue
		var offset := f.agents.position[i] - car.position
		offset.y = 0.0
		var ahead := offset.dot(fwd)
		if ahead <= 0.0 or absf(offset.dot(right)) > p.lane_half_width:
			continue
		var clear := ahead - car.body_length * 0.5 - f.agents.body_size[i].z * 0.5
		nearest = minf(nearest, maxf(clear, 0.0) / car.speed)
	return nearest
