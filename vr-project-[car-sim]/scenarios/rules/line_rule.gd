class_name LineRule
extends RefCounted
## Lines and kerbs, judged on the car's wheels: crossing a solid line, crossing a dashed line
## without first indicating that way, riding on a lane line, and mounting a kerb. The wheels
## crossing one marking within the merge time are one crossing.


static func initial(_p: Dictionary) -> Dictionary:
	return {last_crossed = {}, straddle = Vector2.ZERO}


static func step(p: Dictionary, s: Dictionary, f: RuleFrame, live: bool) -> RuleResult:
	var r := RuleResult.new(s)
	if not live:
		return r
	var car := f.car
	var last: Dictionary = s.last_crossed.duplicate()
	for hit in f.crossings:
		var merged: bool = last.has(hit.marking) and f.elapsed - float(last[hit.marking]) < p.crossing_merge
		last[hit.marking] = f.elapsed
		if merged:
			continue
		match hit.kind:
			RoadMarking.Kind.SOLID, RoadMarking.Kind.DOUBLE_SOLID:
				r.report(p.solid_fault, hit.point, hit.marking)
			RoadMarking.Kind.DASHED:
				if car.indicator != VehicleProbe.Indicator.UNKNOWN \
						and car.indicator_held_for(car.side_of(hit.normal)) < p.indicator_lead:
					r.report(p.no_indicator_fault, hit.point, hit.marking)
			RoadMarking.Kind.KERB:
				r.report(p.kerb_fault, hit.point, hit.marking)
	var straddle := Episode.next(s.straddle, _on_lane_line(f, car.wheels, p.wheel_half_width), f.dt,
		p.grace)
	if Episode.fired(s.straddle, straddle):
		r.report_here(p.straddle_fault, f)
	r.state = {last_crossed = last, straddle = straddle}
	return r


static func finish(_p: Dictionary, s: Dictionary, _f: RuleFrame, _live: bool) -> RuleResult:
	return RuleResult.new(s)


static func _on_lane_line(f: RuleFrame, wheels: PackedVector3Array, half_width: float) -> bool:
	if f.markings == null:
		return false
	for wheel in wheels:
		for marking in f.markings.overlapping(wheel, half_width):
			if RoadMarking.is_lane_kind(f.markings.kind_of(marking)):
				return true
	return false
