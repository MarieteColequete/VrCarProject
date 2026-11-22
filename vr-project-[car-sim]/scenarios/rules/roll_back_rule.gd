class_name RollBackRule
extends RefCounted
## A hill start: the car stopped in the zone is held where it stopped; rolling back further than
## the allowed distance against the direction up the hill is a fault, once per stop. Moving on up
## the hill ends the stop.

## Metres up the hill past where it stopped that count as having moved on.
const MOVED_ON := 2.0


static func initial(_p: Dictionary) -> Dictionary:
	return {held = false, at = Vector3.ZERO, reported = false}


static func step(p: Dictionary, s: Dictionary, f: RuleFrame, live: bool) -> RuleResult:
	var n := s.duplicate()
	var r := RuleResult.new(n)
	if not live:
		return r
	var car := f.car
	if not f.inside(p.zone):
		n.held = false
		return r
	if car.stopped and not n.held:
		n.held = true
		n.at = car.position
		n.reported = false
	if n.held:
		var moved: float = (car.position - n.at).dot(p.direction)
		if moved < -p.max_roll and not n.reported:
			n.reported = true
			r.report_here(p.fault, f)
		elif moved > MOVED_ON:
			n.held = false
	return r


static func finish(_p: Dictionary, s: Dictionary, _f: RuleFrame, _live: bool) -> RuleResult:
	return RuleResult.new(s)
