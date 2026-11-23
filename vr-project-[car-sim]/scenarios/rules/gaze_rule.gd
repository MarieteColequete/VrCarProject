class_name GazeRule
extends RefCounted
## Observation before a manoeuvre: crossing a lane line, or moving off after a stop when that is
## judged, needs a look at the mirror on that side, and over that shoulder when required, within
## the window before; with the interior mirror required, a look at it too. A car with mirrors is
## judged on where its driver looks: a mirror look is the look held within a cone around the
## direction from the eye to that mirror, so a glance with the eyes counts as a head turn does. A
## car without mirrors is judged on the look's angle from the car's forward direction, positive to
## the left. A shoulder look is always that angle. Optionally, looking away from the road while
## moving for too long is a fault of its own.

const INTERIOR := 0
const LEFT_MIRROR := 1
const RIGHT_MIRROR := 2


static func initial(_p: Dictionary) -> Dictionary:
	return {last_seen = {}, last_crossed = {}, stopped_long = false, in_cone = {},
		off_road_since = -1.0, off_road_reported = false}


static func step(p: Dictionary, s: Dictionary, f: RuleFrame, live: bool) -> RuleResult:
	var n := s.duplicate()
	var r := RuleResult.new(n)
	var car := f.car
	if live:
		var seen: Dictionary = s.last_seen.duplicate()
		var in_cone: Dictionary = s.in_cone.duplicate()
		var angle := car.look_angle()
		var has_mirrors := car.mirrors.size() > RIGHT_MIRROR
		for side in [VehicleProbe.Indicator.LEFT, VehicleProbe.Indicator.RIGHT]:
			if has_mirrors:
				var index := LEFT_MIRROR if side == VehicleProbe.Indicator.LEFT else RIGHT_MIRROR
				_held(p, car, index, key(&"mirror", side), f.elapsed, in_cone, seen)
			elif absf(angle - signed(side, p.mirror_angle)) <= p.tolerance:
				seen[key(&"mirror", side)] = f.elapsed
			if absf(angle - signed(side, p.shoulder_angle)) <= p.tolerance:
				seen[key(&"shoulder", side)] = f.elapsed
		if has_mirrors:
			_held(p, car, INTERIOR, &"interior", f.elapsed, in_cone, seen)
		n.last_seen = seen
		n.in_cone = in_cone
		_watch_road(p, n, f, angle, has_mirrors, r)
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


## The name a look is kept under: [param kind] ([code]mirror[/code] or [code]shoulder[/code]) to
## [param side].
static func key(kind: StringName, side: int) -> StringName:
	var left := side == VehicleProbe.Indicator.LEFT
	if kind == &"mirror":
		return &"mirror_left" if left else &"mirror_right"
	return &"shoulder_left" if left else &"shoulder_right"


static func looked(p: Dictionary, s: Dictionary, f: RuleFrame, look: StringName) -> bool:
	return s.last_seen.has(look) and f.elapsed - float(s.last_seen[look]) <= p.window


## Counts a look at mirror [param index] once the look has stayed in its cone for the dwell.
static func _held(p: Dictionary, car: CarState, index: int, look: StringName, elapsed: float,
		in_cone: Dictionary, seen: Dictionary) -> void:
	if car.look_off_mirror(index) > p.mirror_cone:
		in_cone.erase(look)
		return
	var since: float = in_cone.get(look, elapsed)
	in_cone[look] = since
	if elapsed - since >= p.mirror_dwell - 0.0001:
		seen[look] = elapsed


## Judges the eyes off the road: moving, a look neither ahead nor in a mirror for longer than
## [code]eyes_off_road_after[/code] seconds is one fault, until the eyes come back.
static func _watch_road(p: Dictionary, n: Dictionary, f: RuleFrame, angle: float,
		has_mirrors: bool, r: RuleResult) -> void:
	if p.eyes_off_road_after <= 0.0:
		return
	var car := f.car
	var on_road: bool = absf(angle) <= p.road_angle or car.stopped
	if has_mirrors:
		for index in [INTERIOR, LEFT_MIRROR, RIGHT_MIRROR]:
			on_road = on_road or car.look_off_mirror(index) <= p.mirror_cone
	if on_road:
		n.off_road_since = -1.0
		n.off_road_reported = false
		return
	if n.off_road_since < 0.0:
		n.off_road_since = f.elapsed
	elif not n.off_road_reported and f.elapsed - n.off_road_since > p.eyes_off_road_after:
		r.report(p.eyes_off_road_fault, car.position)
		n.off_road_reported = true


static func _judge(p: Dictionary, s: Dictionary, f: RuleFrame, side: int, at: Vector3,
		r: RuleResult) -> void:
	var mirror := looked(p, s, f, key(&"mirror", side))
	if p.require_interior and f.car.mirrors.size() > INTERIOR:
		mirror = mirror and looked(p, s, f, &"interior")
	if not mirror:
		r.report(p.mirror_fault, at)
	if p.require_shoulder and not looked(p, s, f, key(&"shoulder", side)):
		r.report(p.shoulder_fault, at)
