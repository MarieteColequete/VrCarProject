class_name AgentThinker
extends RefCounted
## One road user's thinking: what it decides this tick from a [TrafficSnapshot]. It is a pure
## computation in effect: [method load] copies the road user's state into the thinker on the main
## thread, [method think] reads only those copies and the snapshot and writes only the decision,
## and [AgentLogic.commit] reads the decision back on the main thread.
##
## It holds the copies as its own fields rather than reading the [AgentState] because of how the
## engine runs GDScript on threads: reading a member of another object validates that object
## under one global lock, while a script's own fields are read directly. Thinking reads dozens of
## values per road user, so on worker threads this is the difference between scaling and queuing.

# The road user's state, copied in by load().
var me := 0
var moving := false
var reactive := true
var lane := 0
var upcoming := 0
var progress := 0.0
var current_speed := 0.0
var reaction: StringName = &""
var committed := false
var braking_hard := false
var blocked_for := 0.0
var shift_left := 0.0
var position := Vector3.ZERO
var loop := false
var body_size := Vector3.ONE
var speed := 0.0
var max_accel := 2.0
var comfort_decel := 3.0
var max_decel := 8.0
var hard_brake := 4.0
var min_gap := 2.0
var time_headway := 1.5
var patience := 4.0

## The decision: whether it thought, and what it decided.
var decided := false
var d_speed := 0.0
var d_kind: StringName = &""
var d_leader := 0
var d_braking_hard := false
var d_committed := false
var d_blocked_for := 0.0
## Neighbour lanes found clear; commit checks the markings.
var d_sides := PackedInt64Array()
## Each [code][kind, data][/code].
var d_events: Array = []

var _config: AgentConfig
var _ahead_buffer := TrafficSensor.Leader.new()
var _stop_buffer := TrafficSensor.Leader.new()
var _scratch := TrafficSensor.Leader.new()
var _rule_gap := INF


## Copies road user [param id]'s state [param s]. Main thread. Its configuration never changes, so
## it is copied only the first time.
func load(id: int, s: AgentState) -> void:
	if s.config != _config:
		_load_config(s.config)
	me = id
	moving = s.state == AgentState.State.MOVING
	lane = s.lane
	upcoming = s.upcoming
	progress = s.progress
	current_speed = s.current_speed
	reaction = s.reaction
	committed = s.committed
	braking_hard = s.braking_hard
	blocked_for = s.blocked_for
	shift_left = s.shift_left
	position = s.transform.origin


func _load_config(cfg: AgentConfig) -> void:
	_config = cfg
	reactive = cfg.reactive
	loop = cfg.loop
	body_size = cfg.body_size
	speed = cfg.speed
	max_accel = cfg.max_accel
	comfort_decel = cfg.comfort_decel
	max_decel = cfg.max_decel
	hard_brake = cfg.hard_brake
	min_gap = cfg.min_gap
	time_headway = cfg.time_headway
	patience = cfg.patience


## Decides this tick's speed and reactions from [param snapshot]: following or stopping behind
## what is in the way by the Intelligent Driver Model, keeping the lane's rules, and looking for a
## clear neighbour lane when stuck. Any thread: it creates no object and reads no other object's
## fields but the snapshot's and the sensor buffers'.
func think(snapshot: TrafficSnapshot, dt: float) -> void:
	decided = false
	if not moving or not reactive:
		return
	var route := snapshot.route(lane)
	if route == null:
		return
	decided = true
	d_sides = PackedInt64Array()
	d_events = []
	_rule_gap = INF
	var target := minf(speed, route.speed_limit)
	var ahead: TrafficSensor.Leader = null
	_ahead_buffer.clear()
	if TrafficSensor.sense(snapshot, _ahead_points(snapshot, route, target), body_size.x * 0.45,
			me, _ahead_buffer):
		ahead = _ahead_buffer
	d_committed = committed
	var rule := _rule_kind(route)
	if not rule.is_empty():
		_stop_buffer.clear()
		_stop_buffer.gap = _rule_gap
		if ahead == null or _rule_gap < ahead.gap:
			ahead = _stop_buffer
		else:
			rule = &""
	var gap := ahead.gap if ahead else INF
	var ahead_speed := ahead.speed if ahead else 0.0
	var ahead_body := ahead.body if ahead else 0
	var ahead_road_user := ahead.road_user if ahead else false
	var v := current_speed
	var accel := max_accel if v < target else 0.0
	var kind: StringName = &""
	# Once reacting, the model keeps control until the road user is back at its scripted speed
	# with nothing holding it back, so it neither creeps up on a leader nor lets go too early.
	if ahead and (not reaction.is_empty() or _forced(gap, ahead_speed, v)):
		var model := _idm(v, gap, ahead_speed, target)
		if not reaction.is_empty() and v >= target - 0.01 and model >= 0.0:
			model = 0.0
		else:
			accel = model
			kind = &"stopped" if v + accel * dt < 0.3 else &"following"
			if not rule.is_empty():
				kind = rule
	var needed := _needed_decel(v, gap, ahead_speed) if ahead_body else 0.0
	d_braking_hard = braking_hard
	if needed > hard_brake and not braking_hard:
		d_braking_hard = true
		d_events.append([&"forced_to_brake", {cause = ahead_body, deceleration = needed}])
	elif needed <= hard_brake:
		d_braking_hard = false
	var next := clampf(v + accel * dt, 0.0, target)
	if ahead and (gap <= 0.05 or (v + accel * dt < 0.3 and not kind.is_empty()
			and kind != &"following" and absf(ahead_speed) < 0.1)):
		# Behind something standing still the road user stands still too, rather than creeping
		# up at the model's crawl, and it never moves into what it already touches.
		next = 0.0
		if kind.is_empty() or kind == &"following":
			kind = &"stopped"
	if kind != reaction:
		d_events.append([&"reacted", {kind = &"resumed" if kind.is_empty() else kind,
			cause = ahead_body}])
	d_speed = next
	d_kind = kind
	d_leader = ahead_body
	var blocked := kind == &"stopped" and ahead_body != 0 and not ahead_road_user
	d_blocked_for = blocked_for + dt if blocked else 0.0
	if d_blocked_for >= patience and maxf(shift_left - dt, 0.0) <= 0.0 and route.is_lane:
		for side in [route.left, route.right]:
			var other := snapshot.route(side) if side else null
			if other and _neighbour_clear(snapshot, other, target):
				d_sides.append(side)


## Whether something [param gap] metres ahead, moving at [param ahead_speed], forces a reaction at
## speed [param v]: it is within the gap kept at a reaction's headway, or closing so fast that
## keeping the script would need braking.
func _forced(gap: float, ahead_speed: float, v: float) -> bool:
	if gap <= min_gap + v * 0.5:
		return true
	var closing := v - ahead_speed
	if closing <= 0.0:
		return false
	return closing * closing / (2.0 * maxf(gap - min_gap, 0.01)) > 0.5


## The deceleration that stopping short of what is ahead, keeping the minimum gap, needs at speed
## [param v]; 0 when it is not closing in.
func _needed_decel(v: float, gap: float, ahead_speed: float) -> float:
	var closing := v - ahead_speed
	if closing <= 0.0:
		return 0.0
	return closing * closing / (2.0 * maxf(gap - min_gap, 0.1))


## The Intelligent Driver Model's acceleration behind what is ahead, towards the scripted speed.
func _idm(v: float, gap: float, ahead_speed: float, target: float) -> float:
	var closing := v - ahead_speed
	var wanted := min_gap + maxf(0.0, v * time_headway
		+ v * closing / (2.0 * sqrt(max_accel * comfort_decel)))
	var g := maxf(gap, 0.05)
	var free := 1.0 - pow(v / maxf(target, 0.1), 4.0)
	return maxf(max_accel * (free - (wanted / g) * (wanted / g)), -max_decel)


## The path ahead of the road user's front, as the sensor sweeps it.
func _ahead_points(snapshot: TrafficSnapshot, route: TrafficSnapshot.Route,
		target: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	var front := progress + body_size.z * 0.5
	var look := target * 3.0 + 5.0
	var next := snapshot.route(upcoming) if upcoming else null
	var length := route.length
	for i in TrafficSensor.SEGMENTS + 1:
		var offset := front + look * i / TrafficSensor.SEGMENTS
		if offset > length and next:
			points.append(next.point_at(offset - length))
		else:
			if loop and length > 0.0:
				offset = fposmod(offset, length)
			points.append(route.point_at(offset))
	return points


## The lane rule holding the road user back now, as a reaction kind, with its stop line's gap in
## the rule gap; empty when no rule applies. May commit to the stop line.
func _rule_kind(route: TrafficSnapshot.Route) -> StringName:
	if not route.is_lane:
		return &""
	var front := progress + body_size.z * 0.5
	# The model keeps the minimum gap to a leader; a stop line is kept at about a metre instead.
	var slack := min_gap - 1.0
	var stops := route.crossing_stops
	var busy := route.crossing_busy
	for i in stops.size():
		var crossing_gap := stops[i] - front
		if crossing_gap > -0.5 and busy[i]:
			_rule_gap = crossing_gap + slack
			return &"yielding"
	var gap := route.stop_at - front
	if gap < -0.5 or d_committed:
		return &""
	var v := current_speed
	if route.has_light and (route.light_red or route.light_amber):
		# Stop only where stopping is still possible; past that point, go through.
		if gap >= v * v / (2.0 * max_decel) or v < 0.5:
			_rule_gap = gap + slack
			return &"waiting_light"
		d_committed = true
		return &""
	if route.has_give_way:
		if not route.way_clear:
			_rule_gap = gap + slack
			return &"yielding"
		if gap < 1.5:
			d_committed = true
	return &""


## Whether [param route], a neighbour lane, is clear from a little behind the road user to its
## look-ahead.
func _neighbour_clear(snapshot: TrafficSnapshot, route: TrafficSnapshot.Route,
		target: float) -> bool:
	var at := route.project(position).x
	var behind := 15.0
	var reach := behind + target * 3.0 + 5.0 + body_size.z
	var points := PackedVector3Array()
	for i in TrafficSensor.SEGMENTS + 1:
		points.append(route.point_at(at - behind + reach * i / TrafficSensor.SEGMENTS))
	_scratch.clear()
	return not TrafficSensor.sense(snapshot, points, body_size.x * 0.45, me, _scratch)
