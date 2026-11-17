@tool
class_name ScriptedAgent
extends AnimatableBody3D
## Another road user: a car or a pedestrian that plays its script by the book until it is forced
## to react. The script follows a [Path3D] at a set speed, starting after [member start_delay]
## counted from when it is armed (at once, or when a vehicle enters [member trigger]); it can
## pause once along the way, and loop. While nothing is in its way the agent moves exactly as
## scripted, so the same script always plays out the same way.
##
## The agent's tick is run by the scene's [TrafficSystem]: it thinks on a worker thread from a
## [TrafficSnapshot] of the last tick ([method think]), and its decision is applied on the main
## thread in a fixed order ([method commit]), so traffic runs alongside the player's car and stays
## reproducible.
##
## With [member reactive] on, a [TrafficSensor] looks ahead along the path every tick. When
## something in the way forces it (the player's car, another road user, a pedestrian, an
## obstacle), the agent slows or stops by the Intelligent Driver Model, then accelerates back to
## its scripted speed once the way is clear. It reports what it does through [signal reacted], and
## [signal forced_to_brake] when it had to brake harder than [member hard_brake].
##
## When its path is a [TrafficLane], it also follows the lane's rules: its speed limit, its light,
## giving way to the lanes with priority, and waiting before a crossing in use. At the lane's end it
## continues onto one of the lane's next lanes: the first one listed in [member route], or one
## picked from [member route_seed], so the same seed always takes the same way.
##
## Stuck behind something that is not traffic, such as a parked van or a car standing in the lane,
## for longer than [member patience], it moves into the lane's [member TrafficLane.left] or
## [member TrafficLane.right] neighbour when that lane is clear around it and no solid line or kerb
## of the scenario's markings lies in between; behind a solid line it waits.
##
## Cars sit on the obstacle layer and pedestrians on the pedestrian layer and in the pedestrian
## group (see [Layers]), so the [ContactCheck] tells them apart. Without a
## [CollisionShape3D] child, it builds a box of [member body_size].

signal started
signal finished
## The agent changed what it is doing: [code]&"following"[/code] a slower leader,
## [code]&"stopped"[/code] behind one, [code]&"waiting_light"[/code] at its lane's light,
## [code]&"yielding"[/code] at a give way line or a crossing in use, [code]&"changing_lane"[/code]
## round a blocked lane, or [code]&"resumed"[/code] its script; [param cause] is the body it
## reacts to, null for a lane's rule and on resuming.
signal reacted(kind: StringName, cause: Node3D)
## Something in the way left the agent needing a deceleration beyond [member hard_brake], metres
## per second squared, to stop short of it: the closing speed squared over twice the room left.
signal forced_to_brake(cause: Node3D, deceleration: float)

enum State { WAITING, MOVING, PAUSED, DONE }

@export var path: Path3D
## Metres per second.
@export var speed := 1.4
@export var start_delay := 0.0
## Starts the delay when a vehicle enters this zone; empty to start at once.
@export var trigger: TriggerZone
@export var loop := false
@export var pedestrian := false
## Distance along the path, in metres, where the agent pauses once per lap; negative for none.
@export var pause_at := -1.0
@export var pause_time := 0.0
@export var body_size := Vector3(1.8, 1.4, 4.2)
@export var colour := Color(0.85, 0.75, 0.2)
## On lanes: the lanes to take where a lane offers a choice, in order; others are picked from
## [member route_seed].
@export var route: Array[TrafficLane] = []
@export var route_seed := 0

@export_group("Reactions")
## Looks ahead and reacts to what is in the way; off, it plays its script whatever happens.
@export var reactive := true
## Acceleration back to the scripted speed, metres per second squared.
@export var max_accel := 2.0
## A comfortable deceleration, metres per second squared.
@export var comfort_decel := 3.0
## The hardest deceleration it can manage.
@export var max_decel := 8.0
## Deceleration beyond which braking counts as forced.
@export var hard_brake := 4.0
## Metres it keeps from a stopped leader.
@export var min_gap := 2.0
## Seconds of headway it keeps behind a moving leader once it has to follow one.
@export var time_headway := 1.5
## Seconds stuck behind something that is not traffic before it changes lanes round it.
@export var patience := 4.0
## Seconds a lane change takes.
@export var change_time := 2.0
@export_group("")

var state := State.WAITING
## Distance travelled along the path in the current lap, in metres.
var progress := 0.0
## The speed it moves at now, metres per second: the scripted speed unless it is reacting.
var current_speed := 0.0
## What it is reacting to, as in [signal reacted]; empty while it plays its script.
var reaction: StringName = &""
## What its sensor saw ahead this tick, or null.
var leader: TrafficSensor.Leader

var _braking_hard := false
var _upcoming: TrafficLane
var _rng := RandomNumberGenerator.new()
# The stop line this agent has committed to crossing on the current lane.
var _committed := false
var _blocked_for := 0.0
# The offset from the lane during a lane change, and the seconds left until it has faded out.
var _shift := Vector3.ZERO
var _shift_left := 0.0
var _scenario_root: Scenario

var _armed := false
var _clock := 0.0
var _paused_for := 0.0
var _paused_this_lap := false
var _length := 0.0
var _system: TrafficSystem
# Where the agent stands, kept by the main thread so thinking need not ask the node.
var _origin := Vector3.ZERO

# The decision of the last think, applied by commit.
var _d_speed := 0.0
var _d_kind: StringName = &""
var _d_leader: TrafficSensor.Leader
var _d_braking_hard := false
var _d_committed := false
var _d_rule_gap := INF
var _d_blocked_for := 0.0
# Neighbour lanes found clear; untyped, as a worker thread cannot check a node's script.
var _d_sides: Array = []
var _d_events: Array = []
var _d_ready := false


func _ready() -> void:
	if Engine.is_editor_hint():
		set_physics_process(false)
		return
	collision_layer = Layers.PEDESTRIAN if pedestrian else Layers.OBSTACLE
	collision_mask = 0
	add_to_group(Layers.GROUP_ROAD_USER)
	if pedestrian:
		add_to_group(Layers.GROUP_PEDESTRIAN)
	if not _has_shape():
		BoxBody.build(self, body_size, colour)
	if path and path.curve:
		_length = path.curve.get_baked_length()
	_rng.seed = route_seed
	_upcoming = _choose_next(path as TrafficLane)
	_armed = trigger == null
	if trigger:
		trigger.vehicle_entered.connect(func(_p: VehicleProbe) -> void: _armed = true)
	# Placed directly rather than synchronised through the physics step, which would lose a
	# placement made here and leave a waiting agent standing at the world origin.
	sync_to_physics = false
	_place(0.0)
	set_physics_process(false)
	_system = TrafficSystem.of(self)
	_system.add(self)


func _exit_tree() -> void:
	if _system and is_instance_valid(_system):
		_system.remove(self)


## Seconds until the agent reaches [param offset] along its path at its speed, counting the
## remaining start delay and pause; INF when it will not get there (not armed, done, or past it
## without looping).
func time_to(offset: float) -> float:
	if state == State.DONE or (state == State.WAITING and not _armed):
		return INF
	var remaining := offset - progress
	if remaining < 0.0:
		if not loop:
			return INF
		remaining += _length
	var wait := 0.0
	if state == State.WAITING:
		wait = maxf(start_delay - _clock, 0.0)
	elif state == State.PAUSED:
		wait = maxf(pause_time - _paused_for, 0.0)
	if pause_at >= 0.0 and not _paused_this_lap and pause_at <= offset and state != State.PAUSED:
		wait += pause_time
	return wait + remaining / maxf(script_speed(), 0.001)


## Seconds until the agent reaches the point of its lane_route nearest [param point], world space: on
## its current path, or on the lane it continues onto; INF when its lane_route does not pass within a
## few metres of it.
func time_to_point(point: Vector3) -> float:
	if path == null:
		return INF
	var local := path.to_local(point)
	var offset := path.curve.get_closest_offset(local)
	var off := local - path.curve.sample_baked(offset)
	off.y = 0.0
	if off.length() <= 3.0 and offset >= progress - 0.5:
		return time_to(offset)
	if _upcoming:
		var where := _upcoming.project(point)
		if where.y <= 3.0:
			var to_end := time_to(_length)
			return to_end + where.x / maxf(minf(speed, _limit_of(_upcoming)), 0.001)
	return INF


## The speed the script asks for here: the agent's speed, capped by its lane's limit.
func script_speed() -> float:
	return minf(speed, _limit_of(path as TrafficLane))


## The paths this agent may read while thinking: its own, the one it continues onto, and its
## lane's neighbours; the [TrafficSystem] copies them into the snapshot.
func paths_in_use() -> Array[Path3D]:
	var out: Array[Path3D] = [path, _upcoming]
	var lane := path as TrafficLane
	if lane:
		out.append(lane.left)
		out.append(lane.right)
	return out


## Decides this tick's speed and reactions from [param snapshot], the last committed tick. Runs on
## a worker thread: it reads only the agent's own committed state and the snapshot, and writes only
## the pending decision, which [method commit] applies.
func think(snapshot: TrafficSnapshot, delta: float) -> void:
	_d_ready = false
	_d_events = []
	_d_sides = []
	if state != State.MOVING or not reactive:
		return
	var lane_route := snapshot.route(path)
	if lane_route == null:
		return
	var target := minf(speed, lane_route.speed_limit)
	var ahead := TrafficSensor.sense(snapshot, _ahead(snapshot, lane_route, target), body_size.x * 0.45,
		self)
	_d_committed = _committed
	_d_rule_gap = INF
	var rule := _rule_kind(lane_route)
	if not rule.is_empty():
		var stop := TrafficSensor.Leader.new()
		stop.gap = _d_rule_gap
		if ahead == null or stop.gap < ahead.gap:
			ahead = stop
		else:
			rule = &""
	var v := current_speed
	var accel := max_accel if v < target else 0.0
	var kind: StringName = &""
	# Once reacting, the model keeps control until the agent is back at its scripted speed with
	# nothing holding it back, so it neither creeps up on a leader nor lets go too early.
	if ahead and (not reaction.is_empty() or _forced(ahead, v)):
		var model := _idm(v, ahead, target)
		if not reaction.is_empty() and v >= target - 0.01 and model >= 0.0:
			model = 0.0
		else:
			accel = model
			kind = &"stopped" if v + accel * delta < 0.3 else &"following"
			if not rule.is_empty():
				kind = rule
	var needed := _needed_decel(v, ahead) if ahead and ahead.body else 0.0
	_d_braking_hard = _braking_hard
	if needed > hard_brake and not _braking_hard:
		_d_braking_hard = true
		_d_events.append([&"forced_to_brake", ahead.body, needed])
	elif needed <= hard_brake:
		_d_braking_hard = false
	var next := clampf(v + accel * delta, 0.0, target)
	if ahead and (ahead.gap <= 0.05 or (v + accel * delta < 0.3 and not kind.is_empty()
			and kind != &"following" and absf(ahead.speed) < 0.1)):
		# Behind something standing still the agent stands still too, rather than creeping up at
		# the model's crawl, and it never moves into what it already touches.
		next = 0.0
		if kind.is_empty() or kind == &"following":
			kind = &"stopped"
	if kind != reaction:
		_d_events.append([&"reacted", &"resumed" if kind.is_empty() else kind,
			ahead.body if ahead else null])
	_d_speed = next
	_d_kind = kind
	_d_leader = ahead
	# Changing lanes: which neighbours are clear now; commit checks the markings.
	var blocker: Node3D = ahead.body if ahead else null
	var blocked := kind == &"stopped" and blocker != null and not ahead.road_user
	_d_blocked_for = _blocked_for + delta if blocked else 0.0
	if _d_blocked_for >= patience and maxf(_shift_left - delta, 0.0) <= 0.0 and lane_route.lane:
		for side in [lane_route.left, lane_route.right]:
			var other := snapshot.route(side)
			if other and _neighbour_clear(snapshot, other, target):
				_d_sides.append(side)
	_d_ready = true


## Applies the decision of the last [method think] and moves the agent: the script's timers,
## its progress along the path, lane changes, and its signals. Main thread, in a fixed order.
func commit(delta: float) -> void:
	match state:
		State.WAITING:
			if not _armed:
				return
			_clock += delta
			if _clock >= start_delay:
				state = State.MOVING
				current_speed = script_speed()
				started.emit()
		State.PAUSED:
			_paused_for += delta
			if _paused_for >= pause_time:
				state = State.MOVING
		State.MOVING:
			if not reactive or not _d_ready:
				current_speed = script_speed()
				_advance(current_speed * delta)
				return
			current_speed = _d_speed
			leader = _d_leader
			_braking_hard = _d_braking_hard
			_committed = _d_committed
			_blocked_for = _d_blocked_for
			reaction = _d_kind
			for event: Array in _d_events:
				if event[0] == &"forced_to_brake":
					forced_to_brake.emit(event[1], event[2])
				else:
					reacted.emit(event[1], event[2])
			_shift_left = maxf(_shift_left - delta, 0.0)
			for side: TrafficLane in _d_sides:
				if _markings_allow(side):
					_move_to(side, leader.body if leader else null)
					break
			_d_ready = false
			_advance(current_speed * delta)


## The agent's facing on the ground, the direction it moves in.
func forward() -> Vector3:
	var f := -global_basis.z
	f.y = 0.0
	return f.normalized()


## The point of the path [param offset] metres along it, world space; past the end, the end, or
## round again on a looping path.
func path_point(offset: float) -> Vector3:
	if offset > _length and _upcoming:
		return _upcoming.point_at(offset - _length)
	if loop and _length > 0.0:
		offset = fposmod(offset, _length)
	return path.global_transform * path.curve.sample_baked(clampf(offset, 0.0, _length))


## Whether the agent has reached the end of its path for good.
func is_done() -> bool:
	return state == State.DONE


## The distance along the path of its point nearest [param point], world space; the offset to
## pass to [method time_to].
func offset_nearest(point: Vector3) -> float:
	return path.curve.get_closest_offset(path.to_local(point))


## Whether [param lane_route], a neighbour lane, is clear from a little behind the agent to its
## look-ahead.
func _neighbour_clear(snapshot: TrafficSnapshot, lane_route: TrafficSnapshot.Route,
		target: float) -> bool:
	var at := lane_route.project(_origin).x
	var behind := 15.0
	var reach := behind + target * 3.0 + 5.0 + body_size.z
	var points := PackedVector3Array()
	for i in TrafficSensor.SEGMENTS + 1:
		points.append(lane_route.point_at(at - behind + reach * i / TrafficSensor.SEGMENTS))
	return TrafficSensor.sense(snapshot, points, body_size.x * 0.45, self) == null


## Whether the scenario's markings let the agent move across into [param target]: no solid line
## or kerb lies on the way. Main thread.
func _markings_allow(target: TrafficLane) -> bool:
	var root := _scenario()
	if root == null:
		return true
	var at := target.project(global_position).x
	var across := target.point_at(at + body_size.z)
	for hit in root.marking_index().crossings(global_position, across):
		var kind := hit.marking.kind
		if kind == RoadMarking.Kind.SOLID or kind == RoadMarking.Kind.DOUBLE_SOLID \
				or kind == RoadMarking.Kind.KERB:
			return false
	return true


func _move_to(target: TrafficLane, blocker: Node3D) -> void:
	var from := global_position
	var at := target.project(from).x
	_enter(target)
	progress = at
	_shift = from - target.point_at(at)
	_shift.y = 0.0
	_shift_left = change_time
	_blocked_for = 0.0
	reaction = &"changing_lane"
	reacted.emit(reaction, blocker)


## The scenario the agent belongs to, for its road markings; null outside one.
func _scenario() -> Scenario:
	if _scenario_root == null:
		var node := get_parent()
		while node and not node is Scenario:
			node = node.get_parent()
		_scenario_root = node as Scenario
	return _scenario_root


## Whether [param ahead] forces a reaction at speed [param v]: it is within the gap kept at a
## reaction's headway, or closing so fast that keeping the script would need braking.
func _forced(ahead: TrafficSensor.Leader, v: float) -> bool:
	if ahead.gap <= min_gap + v * 0.5:
		return true
	var closing := v - ahead.speed
	if closing <= 0.0:
		return false
	return closing * closing / (2.0 * maxf(ahead.gap - min_gap, 0.01)) > 0.5


## The deceleration that stopping short of [param ahead], keeping [member min_gap], needs at
## speed [param v]; 0 when it is not closing in.
func _needed_decel(v: float, ahead: TrafficSensor.Leader) -> float:
	var closing := v - ahead.speed
	if closing <= 0.0:
		return 0.0
	return closing * closing / (2.0 * maxf(ahead.gap - min_gap, 0.1))


## The Intelligent Driver Model's acceleration behind [param ahead], towards the scripted speed.
func _idm(v: float, ahead: TrafficSensor.Leader, target: float) -> float:
	var closing := v - ahead.speed
	var wanted := min_gap + maxf(0.0, v * time_headway
		+ v * closing / (2.0 * sqrt(max_accel * comfort_decel)))
	var gap := maxf(ahead.gap, 0.05)
	var free := 1.0 - pow(v / maxf(target, 0.1), 4.0)
	return maxf(max_accel * (free - (wanted / gap) * (wanted / gap)), -max_decel)


## The path ahead of the agent's front, as the sensor sweeps it, from the snapshot's routes.
func _ahead(snapshot: TrafficSnapshot, lane_route: TrafficSnapshot.Route,
		target: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	var front := progress + body_size.z * 0.5
	var look := target * 3.0 + 5.0
	var next := snapshot.route(_upcoming) if _upcoming else null
	for i in TrafficSensor.SEGMENTS + 1:
		var offset := front + look * i / TrafficSensor.SEGMENTS
		if offset > lane_route.length and next:
			points.append(next.point_at(offset - lane_route.length))
		else:
			if loop and lane_route.length > 0.0:
				offset = fposmod(offset, lane_route.length)
			points.append(lane_route.point_at(offset))
	return points


func _advance(step: float) -> void:
	var length := _length
	progress += step
	if pause_at >= 0.0 and not _paused_this_lap and progress >= pause_at:
		progress = pause_at
		_paused_this_lap = true
		_paused_for = 0.0
		state = State.PAUSED
	elif progress >= length and _upcoming:
		progress -= length
		_enter(_upcoming)
	elif progress >= length:
		if loop:
			progress = fmod(progress, length)
			_paused_this_lap = false
		else:
			progress = length
			state = State.DONE
			finished.emit()
	_place(progress)


## The lane rule holding the agent back now, as a reaction kind, with its stop line's gap in
## the pending decision; empty when no rule applies. Reads the rules the snapshot evaluated.
func _rule_kind(lane_route: TrafficSnapshot.Route) -> StringName:
	if lane_route.lane == null:
		return &""
	var front := progress + body_size.z * 0.5
	# The model keeps min_gap to a leader; a stop line is kept at about a metre instead.
	var slack := min_gap - 1.0
	for i in lane_route.crossing_stops.size():
		var gap := lane_route.crossing_stops[i] - front
		if gap > -0.5 and lane_route.crossing_busy[i]:
			_d_rule_gap = gap + slack
			return &"yielding"
	var gap := lane_route.stop_at - front
	if gap < -0.5 or _d_committed:
		return &""
	var v := current_speed
	if lane_route.has_light and (lane_route.light_red or lane_route.light_amber):
		# Stop only where stopping is still possible; past that point, go through.
		if gap >= v * v / (2.0 * max_decel) or v < 0.5:
			_d_rule_gap = gap + slack
			return &"waiting_light"
		_d_committed = true
		return &""
	if lane_route.has_give_way:
		if not lane_route.way_clear:
			_d_rule_gap = gap + slack
			return &"yielding"
		if gap < 1.5:
			_d_committed = true
	return &""


func _enter(lane: TrafficLane) -> void:
	path = lane
	_length = lane.length()
	_committed = false
	_upcoming = _choose_next(lane)


func _choose_next(lane: TrafficLane) -> TrafficLane:
	if lane == null or lane.next.is_empty():
		return null
	for wanted in route:
		if lane.next.has(wanted):
			return wanted
	return lane.next[_rng.randi_range(0, lane.next.size() - 1)]


static func _limit_of(lane: TrafficLane) -> float:
	return lane.speed_limit if lane and lane.speed_limit > 0.0 else INF


func _place(offset: float) -> void:
	if path == null or path.curve == null:
		return
	var curve := path.curve
	var length := _length if _length > 0.0 else curve.get_baked_length()
	var here := path.global_transform * curve.sample_baked(offset)
	var ahead := path.global_transform * curve.sample_baked(minf(offset + 0.5, length))
	var behind := path.global_transform * curve.sample_baked(maxf(offset - 0.5, 0.0))
	var tangent := ahead - behind
	tangent.y = 0.0
	if _shift_left > 0.0 and change_time > 0.0:
		# Mid lane change: the agent eases from where it was onto the lane, heading across.
		var weight := smoothstep(0.0, 1.0, _shift_left / change_time)
		here += _shift * weight
		if tangent.length() > 0.001:
			tangent = tangent.normalized() - _shift.normalized() * 0.25 * weight
	var facing := global_basis
	if tangent.length() > 0.001:
		facing = Basis.looking_at(tangent.normalized(), Vector3.UP)
	global_transform = Transform3D(facing, here)
	_origin = here


func _has_shape() -> bool:
	for child in get_children():
		if child is CollisionShape3D:
			return true
	return false


func _get_configuration_warnings() -> PackedStringArray:
	if path == null:
		return ["Set the path the agent follows."]
	return []
