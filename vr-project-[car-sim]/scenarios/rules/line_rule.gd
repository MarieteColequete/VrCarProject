class_name LineRule
extends RefCounted
## Lines and kerbs, judged on the car's wheels: crossing a solid line, crossing a dashed line
## without first indicating that way, riding on a lane line, and hitting a kerb: a tyre touching
## or crossing a kerb line. Kerbs are solid, so a tyre usually stops against one; the body may
## overhang it freely. The wheels crossing or touching one marking within the merge time are one
## fault.


static func initial(_p: Dictionary) -> Dictionary:
	return {last_crossed = {}, straddle = Vector2.ZERO}


static func step(p: Dictionary, s: Dictionary, f: RuleFrame, live: bool) -> RuleResult:
	var r := RuleResult.new(s)
	if not live:
		return r
	var car := f.car
	var last: Dictionary = s.last_crossed.duplicate()
	for touch in _on_kerb(f, car.wheels, car.forward * float(p.wheel_half_length),
			p.wheel_half_width + p.kerb_reach):
		var marking: int = touch[0]
		var touching: bool = last.has(marking) and f.elapsed - float(last[marking]) < p.crossing_merge
		last[marking] = f.elapsed
		if not touching:
			r.report(p.kerb_fault, touch[1], marking)
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


## The kerb lines a tyre touches, [code][marking, wheel][/code]: its centre, front, or back
## ([param along] from the centre) within its half width and [param reach] of one. The front
## counts for a tyre driven straight at a kerb, which meets it head on.
static func _on_kerb(f: RuleFrame, wheels: PackedVector3Array, along: Vector3,
		reach: float) -> Array:
	var out: Array = []
	if f.markings == null:
		return out
	for wheel in wheels:
		for point in [wheel, wheel + along, wheel - along]:
			for marking in f.markings.overlapping(point, reach):
				if f.markings.kind_of(marking) == RoadMarking.Kind.KERB and not _has(out, marking):
					out.append([marking, wheel])
	return out


static func _has(touches: Array, marking: int) -> bool:
	for touch: Array in touches:
		if touch[0] == marking:
			return true
	return false


static func _on_lane_line(f: RuleFrame, wheels: PackedVector3Array, half_width: float) -> bool:
	if f.markings == null:
		return false
	for wheel in wheels:
		for marking in f.markings.overlapping(wheel, half_width):
			if RoadMarking.is_lane_kind(f.markings.kind_of(marking)):
				return true
	return false
