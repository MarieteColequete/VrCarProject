class_name RouteRule
extends RefCounted
## A lane the car should follow, given by a path along the lane's centre in the direction of
## traffic: drifting out of the lane, leaving the road, and driving against the lane, each one
## fault per episode, judged only while the car is alongside the path.


static func initial(_p: Dictionary) -> Dictionary:
	return {lateral = 0.0, progress = 0.0, lane = Vector2.ZERO, road = Vector2.ZERO,
		wrong = Vector2.ZERO}


static func step(p: Dictionary, s: Dictionary, f: RuleFrame, live: bool) -> RuleResult:
	var r := RuleResult.new(s)
	var path: LaneData = f.lanes.get(p.path)
	if not live or path == null:
		return r
	var car := f.car
	var n := s.duplicate()
	r.state = n
	var on := path.project(car.position)
	n.progress = on.x
	if n.progress <= 0.01 or n.progress >= path.length - 0.01:
		return r
	n.lateral = on.y
	var tangent := path.ground_tangent(n.progress)
	var against: bool = car.forward.dot(tangent.normalized()) < -0.5 \
		and absf(car.speed) > p.wrong_way_speed
	var road := Episode.next(s.road, n.lateral > p.road_offset, f.dt, p.lane_grace)
	n.road = road
	if Episode.fired(s.road, road):
		r.report_here(p.road_fault, f)
	else:
		var lane := Episode.next(s.lane, n.lateral > p.lane_offset and n.lateral <= p.road_offset,
			f.dt, p.lane_grace)
		n.lane = lane
		if Episode.fired(s.lane, lane):
			r.report_here(p.lane_fault, f)
	var wrong := Episode.next(s.wrong, against, f.dt, p.wrong_way_grace)
	n.wrong = wrong
	if Episode.fired(s.wrong, wrong):
		r.report_here(p.wrong_way_fault, f)
	return r


static func finish(_p: Dictionary, s: Dictionary, _f: RuleFrame, _live: bool) -> RuleResult:
	return RuleResult.new(s)
