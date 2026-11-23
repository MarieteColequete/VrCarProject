class_name GoalRule
extends RefCounted
## The end of a step, or of the attempt: entering the zone completes the step when one is set, and
## otherwise the attempt.


static func initial(_p: Dictionary) -> Dictionary:
	return {}


static func step(p: Dictionary, s: Dictionary, f: RuleFrame, live: bool) -> RuleResult:
	var r := RuleResult.new(s)
	if live and f.entered(p.zone):
		if p.step >= 0:
			r.complete_step = p.step
		else:
			r.complete = true
	return r
