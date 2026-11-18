class_name ContactRule
extends RefCounted
## Contact between the car and a road user or obstacle; a pedestrian gives the pedestrian fault.
## Each body is reported once per attempt.


static func initial(_p: Dictionary) -> Dictionary:
	return {touched = PackedInt64Array()}


static func step(p: Dictionary, s: Dictionary, f: RuleFrame, live: bool) -> RuleResult:
	var r := RuleResult.new(s)
	if not live:
		return r
	var touched: PackedInt64Array = s.touched
	for event in f.events_of(&"contact"):
		if touched.has(event.entity):
			continue
		touched = touched.duplicate()
		touched.append(event.entity)
		r.report_here(p.pedestrian_fault if event.data.pedestrian else p.obstacle_fault, f,
			event.entity)
	r.state = {touched = touched}
	return r


static func finish(_p: Dictionary, s: Dictionary, _f: RuleFrame, _live: bool) -> RuleResult:
	return RuleResult.new(s)
