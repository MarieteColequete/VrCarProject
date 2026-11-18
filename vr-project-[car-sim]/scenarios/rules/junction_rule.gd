class_name JunctionRule
extends RefCounted
## Turning at a junction: which way the car leaves, and whether it signalled that way. The
## indicator is read as the car leaves the approach, or at the exit when judging on exit (the
## roundabout rule). Leaving by an exit needing a side the indicator had not shown for the lead
## time is turning without indicating; leaving by an exit the route does not allow is a wrong turn.


static func initial(_p: Dictionary) -> Dictionary:
	return {held = {}, judged = false}


static func step(p: Dictionary, s: Dictionary, f: RuleFrame, live: bool) -> RuleResult:
	var n := s.duplicate()
	var r := RuleResult.new(n)
	if not live:
		return r
	var car := f.car
	if not p.judge_on_exit and f.exited(p.approach):
		n.judged = false
		n.held = _held(car)
	for exit: Dictionary in p.exits:
		if not f.entered(exit.zone) or n.judged:
			continue
		if p.judge_on_exit:
			n.held = _held(car)
		elif n.held.is_empty():
			continue
		n.judged = true
		if not exit.allowed:
			r.report_here(p.wrong_turn_fault, f)
		if exit.side != VehicleProbe.Indicator.OFF and car.indicator != VehicleProbe.Indicator.UNKNOWN \
				and float(n.held.get(exit.side, 0.0)) < p.indicator_lead:
			r.report_here(p.indicator_fault, f)
	return r


static func finish(_p: Dictionary, s: Dictionary, _f: RuleFrame, _live: bool) -> RuleResult:
	return RuleResult.new(s)


static func _held(car: CarState) -> Dictionary:
	return {VehicleProbe.Indicator.LEFT: car.indicator_held_for(VehicleProbe.Indicator.LEFT),
		VehicleProbe.Indicator.RIGHT: car.indicator_held_for(VehicleProbe.Indicator.RIGHT)}
