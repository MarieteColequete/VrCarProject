class_name GazeRule
extends RefCounted
## Observation before a manoeuvre: crossing a lane line, or moving off after a stop when that is
## judged, needs a look at the mirror on that side, and over that shoulder when required, within
## the window before. Looks are angles from the car's forward direction, positive to the left.


static func initial(_p: Dictionary) -> Dictionary:
	return {last_seen = {}, last_crossed = {}, stopped_long = false}


static func step(p: Dictionary, s: Dictionary, f: RuleFrame, live: bool) -> RuleResult:
	var n := s.duplicate()
	var r := RuleResult.new(n)
	var car := f.car
	if live:
		var seen: Dictionary = s.last_seen.duplicate()
		var angle := car.look_angle()
		for side in [VehicleProbe.Indicator.LEFT, VehicleProbe.Indicator.RIGHT]:
			for target_angle: float in [p.mirror_angle, p.shoulder_angle]:
				var target := signed(side, target_angle)
				if absf(angle - target) <= p.tolerance:
					seen[target] = f.elapsed
		n.last_seen = seen
		if car.direction == VehicleProbe.Direction.STOPPED and car.stopped_for >= p.move_off_after:
			n.stopped_long = true
		var crossed: Dictionary = s.last_crossed.duplicate()
		for hit in f.crossings:
			if not RoadMarking.is_lane_kind(hit.kind):
				continue
			var merged: bool = crossed.has(hit.marking) \
				and f.elapsed - float(crossed[hit.marking]) < p.crossing_merge
			crossed[hit.marking] = f.elapsed
			if not merged:
				_judge(p, n, f, car.side_of(hit.normal), hit.point, r)
		n.last_crossed = crossed
	if car.started_moving != -1:
		if p.check_move_off and n.stopped_long and live:
			_judge(p, n, f, p.move_off_side, car.position, r)
		n.stopped_long = false
	return r


static func finish(_p: Dictionary, s: Dictionary, _f: RuleFrame, _live: bool) -> RuleResult:
	return RuleResult.new(s)


static func signed(side: int, angle: float) -> float:
	return angle if side == VehicleProbe.Indicator.LEFT else -angle


static func looked(p: Dictionary, s: Dictionary, f: RuleFrame, side: int, angle: float) -> bool:
	var target := signed(side, angle)
	return s.last_seen.has(target) and f.elapsed - float(s.last_seen[target]) <= p.window


static func _judge(p: Dictionary, s: Dictionary, f: RuleFrame, side: int, at: Vector3,
		r: RuleResult) -> void:
	if not looked(p, s, f, side, p.mirror_angle):
		r.report(p.mirror_fault, at)
	if p.require_shoulder and not looked(p, s, f, side, p.shoulder_angle):
		r.report(p.shoulder_fault, at)
