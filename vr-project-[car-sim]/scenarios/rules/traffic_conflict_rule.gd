class_name TrafficConflictRule
extends RefCounted
## Making other road users react: each time a road user is forced to brake hard because of the
## car, such as by cutting in or pulling out in front of it, is a fault. It watches the given road
## users, or every one, including those spawned during the attempt.


static func initial(_p: Dictionary) -> Dictionary:
	return {}


static func step(p: Dictionary, s: Dictionary, f: RuleFrame, live: bool) -> RuleResult:
	var r := RuleResult.new(s)
	if not live or f.car == null:
		return r
	for event in f.events_of(&"forced_to_brake"):
		var watched: PackedInt64Array = p.agents
		if (watched.is_empty() or watched.has(event.entity)) and event.data.cause == f.car.entity:
			r.report_here(p.fault, f, event.entity)
	return r
