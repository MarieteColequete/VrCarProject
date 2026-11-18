class_name AgentLogic
extends RefCounted
## How a road user drives, as pure functions of its [AgentState]: it plays its script by the book
## (follow its path at its speed after its start delay, pause once along the way, loop) until it
## is forced to react. Thinking is the [AgentThinker]'s; committing ([method commit]) turns its
## decision into the next state and the events of the tick.
##
## While reactive, a sensor looks ahead along the path; when something in the way forces it, the
## road user slows or stops by the Intelligent Driver Model, then accelerates back to its scripted
## speed once the way is clear. On a [TrafficLane] it also keeps the lane's rules: its speed limit,
## its light, giving way to the lanes with priority, and waiting before a crossing in use. Stuck
## behind something that is not traffic for longer than its patience, it moves into a clear
## neighbour lane when no solid line or kerb lies in between.


## A road user's first state on [param lane], standing at the lane's start.
static func spawn(config: AgentConfig, lane: LaneData, lanes: Dictionary) -> AgentState:
	var s := AgentState.new()
	s.config = config
	s.lane = lane.id
	s.length = lane.length
	var rng := RandomNumberGenerator.new()
	rng.seed = config.route_seed
	s.rng_state = rng.state
	s.upcoming = _choose_next(s, lane)
	s.armed = config.trigger == 0
	s.transform = place(s, lane)
	s.jumped = true
	return s


static func limit_of(lane: LaneData) -> float:
	return lane.speed_limit if lane else INF


## The speed the script asks for here: the road user's speed, capped by its lane's limit.
static func script_speed(s: AgentState, lanes: Dictionary) -> float:
	return minf(s.config.speed, limit_of(lanes.get(s.lane)))


## Seconds until the road user reaches [param offset] along its path at its speed, counting the
## remaining start delay and pause; INF when it will not get there.
static func time_to(s: AgentState, offset: float, lanes: Dictionary) -> float:
	var cfg := s.config
	if s.state == AgentState.State.DONE or (s.state == AgentState.State.WAITING and not s.armed):
		return INF
	var remaining := offset - s.progress
	if remaining < 0.0:
		if not cfg.loop:
			return INF
		remaining += s.length
	var wait := 0.0
	if s.state == AgentState.State.WAITING:
		wait = maxf(cfg.start_delay - s.clock, 0.0)
	elif s.state == AgentState.State.PAUSED:
		wait = maxf(cfg.pause_time - s.paused_for, 0.0)
	if cfg.pause_at >= 0.0 and not s.paused_this_lap and cfg.pause_at <= offset \
			and s.state != AgentState.State.PAUSED:
		wait += cfg.pause_time
	return wait + remaining / maxf(script_speed(s, lanes), 0.001)


## Seconds until the road user reaches the point of its route nearest [param point]: on its
## current path, or on the lane it continues onto; INF when its route does not pass within a few
## metres of it.
static func time_to_point(s: AgentState, point: Vector3, lanes: Dictionary) -> float:
	var lane: LaneData = lanes.get(s.lane)
	if lane == null:
		return INF
	var where := lane.project(point)
	if where.y <= 3.0 and where.x >= s.progress - 0.5:
		return time_to(s, where.x, lanes)
	var upcoming: LaneData = lanes.get(s.upcoming)
	if upcoming:
		var there := upcoming.project(point)
		if there.y <= 3.0:
			return time_to(s, s.length, lanes) \
				+ there.x / maxf(minf(s.config.speed, limit_of(upcoming)), 0.001)
	return INF


## The lanes a road user may read while thinking: its own, the next, and its neighbours.
static func lanes_in_use(s: AgentState, lanes: Dictionary) -> PackedInt64Array:
	var out := PackedInt64Array([s.lane])
	if s.upcoming:
		out.append(s.upcoming)
	var lane: LaneData = lanes.get(s.lane)
	if lane:
		if lane.left:
			out.append(lane.left)
		if lane.right:
			out.append(lane.right)
	return out


## The next state of road user [param me] after [param dt] seconds, applying [param decision]
## (null when it did not think), written into [param n], a fresh state; returns the tick's events
## as [code][kind, data][/code] pairs. [param armed_now] is whether its trigger zone holds the
## car; [param markings] the scenario's [MarkingIndex], or null. Main thread: it reads other
## objects and, on a lane change, creates marking hits.
static func commit(s: AgentState, me: int, decision: AgentThinker, lanes: Dictionary,
		markings: MarkingIndex, armed_now: bool, dt: float, n: AgentState) -> Array:
	s.copy_into(n)
	var events := []
	var cfg := n.config
	match n.state:
		AgentState.State.WAITING:
			n.armed = n.armed or armed_now
			if n.armed:
				n.clock += dt
				if n.clock >= cfg.start_delay:
					n.state = AgentState.State.MOVING
					n.current_speed = script_speed(n, lanes)
					events.append([&"agent_started", {}])
		AgentState.State.PAUSED:
			n.paused_for += dt
			if n.paused_for >= cfg.pause_time:
				n.state = AgentState.State.MOVING
		AgentState.State.MOVING:
			if not cfg.reactive or decision == null:
				n.current_speed = script_speed(n, lanes)
				_advance(n, n.current_speed * dt, lanes, events)
			else:
				n.current_speed = decision.d_speed
				n.leader = decision.d_leader
				n.braking_hard = decision.d_braking_hard
				n.committed = decision.d_committed
				n.blocked_for = decision.d_blocked_for
				n.reaction = decision.d_kind
				events.append_array(decision.d_events)
				n.shift_left = maxf(n.shift_left - dt, 0.0)
				for side in decision.d_sides:
					var target: LaneData = lanes.get(side)
					if target and _markings_allow(n, target, markings):
						_move_to(n, target, decision.d_leader, events)
						break
				_advance(n, n.current_speed * dt, lanes, events)
	return events


## Where a road user in state [param s] stands on [param lane]: on the curve at its progress,
## facing along it, eased across during a lane change.
static func place(s: AgentState, lane: LaneData) -> Transform3D:
	if lane == null or lane.curve == null:
		return s.transform
	var curve := lane.curve
	var length := s.length if s.length > 0.0 else lane.length
	var offset := s.progress
	var here := lane.transform * curve.sample_baked(offset)
	var ahead := lane.transform * curve.sample_baked(minf(offset + 0.5, length))
	var behind := lane.transform * curve.sample_baked(maxf(offset - 0.5, 0.0))
	var tangent := ahead - behind
	tangent.y = 0.0
	var change_time := s.config.change_time
	if s.shift_left > 0.0 and change_time > 0.0:
		# Mid lane change: it eases from where it was onto the lane, heading across.
		var weight := smoothstep(0.0, 1.0, s.shift_left / change_time)
		here += s.shift * weight
		if tangent.length() > 0.001:
			tangent = tangent.normalized() - s.shift.normalized() * 0.25 * weight
	var facing := s.transform.basis
	if tangent.length() > 0.001:
		facing = Basis.looking_at(tangent.normalized(), Vector3.UP)
	return Transform3D(facing, here)


static func _advance(n: AgentState, step: float, lanes: Dictionary, events: Array) -> void:
	var cfg := n.config
	n.progress += step
	if cfg.pause_at >= 0.0 and not n.paused_this_lap and n.progress >= cfg.pause_at:
		n.progress = cfg.pause_at
		n.paused_this_lap = true
		n.paused_for = 0.0
		n.state = AgentState.State.PAUSED
	elif n.progress >= n.length and n.upcoming:
		n.progress -= n.length
		_enter(n, lanes.get(n.upcoming))
	elif n.progress >= n.length:
		if cfg.loop:
			n.progress = fmod(n.progress, n.length)
			n.paused_this_lap = false
			# Jumped back to the path's start: drawn there, not sliding back across the world.
			n.jumped = true
		else:
			n.progress = n.length
			n.state = AgentState.State.DONE
			events.append([&"agent_finished", {}])
	n.transform = place(n, lanes.get(n.lane))


static func _enter(n: AgentState, lane: LaneData) -> void:
	n.lane = lane.id
	n.length = lane.length
	n.committed = false
	n.upcoming = _choose_next(n, lane)


static func _choose_next(n: AgentState, lane: LaneData) -> int:
	if lane == null or not lane.is_lane or lane.next.is_empty():
		return 0
	for wanted in n.config.route:
		if lane.next.has(wanted):
			return wanted
	var rng := RandomNumberGenerator.new()
	rng.state = n.rng_state
	var pick := lane.next[rng.randi_range(0, lane.next.size() - 1)]
	n.rng_state = rng.state
	return pick


static func _move_to(n: AgentState, target: LaneData, blocker: int, events: Array) -> void:
	var from := n.transform.origin
	var at := target.project(from).x
	_enter(n, target)
	n.progress = at
	n.shift = from - target.point_at(at)
	n.shift.y = 0.0
	n.shift_left = n.config.change_time
	n.blocked_for = 0.0
	n.reaction = &"changing_lane"
	events.append([&"reacted", {kind = n.reaction, cause = blocker}])


## Whether the markings let the road user move across into [param target]: no solid line or kerb
## lies on the way.
static func _markings_allow(n: AgentState, target: LaneData, markings: MarkingIndex) -> bool:
	if markings == null:
		return true
	var from := n.transform.origin
	var at := target.project(from).x
	var across := target.point_at(at + n.config.body_size.z)
	for hit in markings.crossings(from, across):
		if hit.kind == RoadMarking.Kind.SOLID or hit.kind == RoadMarking.Kind.DOUBLE_SOLID \
				or hit.kind == RoadMarking.Kind.KERB:
			return false
	return true
