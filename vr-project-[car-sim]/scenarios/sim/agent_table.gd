class_name AgentTable
extends RefCounted
## The road users as columns: one packed array per field, one row per road user, the same columns
## the world's agent component holds. How a road user drives is the functions below, each over a
## row of the table: it plays its script by the book (follow its path at its speed after its start
## delay, pause once along the way, loop) until it is forced to react.
##
## While reactive, a sensor looks ahead along the path; when something in the way forces it, the
## road user slows or stops by the Intelligent Driver Model, then accelerates back to its scripted
## speed once the way is clear. On a [TrafficLane] it also keeps the lane's rules: its speed limit,
## its light, giving way to the lanes with priority, and waiting before a crossing in use. Stuck
## behind something that is not traffic for longer than its patience, it moves into a clear
## neighbour lane when no solid line or kerb lies in between.
##
## A car drives its path on the shared vehicle core ([PlanarVehicle], its [CarSpec] from
## [TrafficSpecs]): the model above gives the speed it wants, slowed ahead of bends to what it
## takes them at, and the engine, the brakes and the tyres give what they can. It steers to keep
## its lane, so it sits a little off the curve and at a small angle to it ([member lateral],
## [member heading]), and a lane change is steering across to the next lane. Walkers and scripted
## road users that do not react keep to their path exactly.
##
## A tick takes a copy of the world's columns ([method copy_of]), thinks every row
## ([method think], on worker threads: it reads the table's own arrays and the snapshot and writes
## only its row of the decision columns), commits every row ([method commit], main thread), and
## hands the new columns back whole ([method write_to]). The world's arrays are never changed in
## place, so the copy is the next tick's state, built as a value.

enum State { WAITING, MOVING, PAUSED, DONE }
## What a road user reacts to; [constant NONE] while it plays its script.
enum Kind { NONE, FOLLOWING, STOPPED, WAITING_LIGHT, YIELDING, CHANGING_LANE }

## The indices of what is ahead, as [method TrafficSensor.sense] writes it.
const AHEAD_FOUND := 0
const AHEAD_ENTITY := 1
const AHEAD_GAP := 2
const AHEAD_SPEED := 3
const AHEAD_ROAD_USER := 4
## Each [enum Kind] as it appears in the [code]&"reacted"[/code] events.
const KIND_NAMES: Array[StringName] = [&"", &"following", &"stopped", &"waiting_light",
	&"yielding", &"changing_lane"]

## The columns that change as road users drive, with their starting values.
const DYNAMIC := {
	state = 0, progress = 0.0, current_speed = 0.0, reaction = 0, lane = 0, length = 0.0,
	upcoming = 0, rng_state = 0, committed = false, blocked_for = 0.0, shift = Vector3.ZERO,
	shift_left = 0.0, armed = false, clock = 0.0, paused_for = 0.0, paused_this_lap = false,
	braking_hard = false, position = Vector3.ZERO, facing = Vector3.FORWARD, grade = 0.0,
	jumped = false,
	leader = 0, lateral = 0.0, heading = 0.0, side_speed = 0.0, yaw_rate = 0.0, steer = 0.0,
	crashed = false,
}
## The columns of what a road user is and how it drives, set when it spawns and never changed.
const CONFIG := {
	name = &"", speed = 1.4, start_delay = 0.0, trigger = 0, loop = false, pedestrian = false,
	pause_at = -1.0, pause_time = 0.0, body_size = Vector3(1.8, 1.4, 4.2),
	colour = Color(0.85, 0.75, 0.2), route = [], route_seed = 0, reactive = true,
	max_accel = 2.0, comfort_decel = 3.0, max_decel = 8.0, hard_brake = 4.0, min_gap = 2.0,
	time_headway = 1.5, patience = 4.0, change_time = 2.0, start_at = 0.0, goal_lane = 0,
	goal_at = -1.0, model = "", spec = -1, max_lateral = 3.5,
}

var ids := PackedInt64Array()

# The dynamic columns.
var state := PackedInt64Array()
## Distance along the current path in this lap, metres.
var progress := PackedFloat64Array()
var current_speed := PackedFloat64Array()
var reaction := PackedInt64Array()
## The lane entity it is on, its length, and the lane it continues onto (0 for none).
var lane := PackedInt64Array()
var length := PackedFloat64Array()
var upcoming := PackedInt64Array()
## The generator of its route choices, as its state.
var rng_state := PackedInt64Array()
var committed := PackedByteArray()
var blocked_for := PackedFloat64Array()
## The offset from the lane during a lane change, and the seconds left until it fades out.
var shift := PackedVector3Array()
var shift_left := PackedFloat64Array()
var armed := PackedByteArray()
var clock := PackedFloat64Array()
var paused_for := PackedFloat64Array()
var paused_this_lap := PackedByteArray()
var braking_hard := PackedByteArray()
## Where it stands, and its facing on the ground.
var position := PackedVector3Array()
var facing := PackedVector3Array()
## The sine of its lane's slope where it stands, along its facing: positive uphill.
var grade := PackedFloat64Array()
## It jumped this tick (spawned, or wrapped round a loop), so a view draws it there at once.
var jumped := PackedByteArray()
## What its sensor saw ahead, the entity, or 0.
var leader := PackedInt64Array()
## How far left of its path it is, metres, and its heading's angle to the path, radians, left
## positive.
var lateral := PackedFloat64Array()
var heading := PackedFloat64Array()
## Its speed to its left, m/s, its yaw rate, rad/s, and its front wheels' angle, radians.
var side_speed := PackedFloat64Array()
var yaw_rate := PackedFloat64Array()
var steer := PackedFloat64Array()
## Knocked off its lane by the player's car ([Impacts]): it brakes to a halt where it is.
var crashed := PackedByteArray()

# The configuration columns.
var name: Array = []
## Metres per second.
var speed := PackedFloat64Array()
var start_delay := PackedFloat64Array()
## The zone whose entry arms the start delay; 0 to start at once.
var trigger := PackedInt64Array()
var loop := PackedByteArray()
var pedestrian := PackedByteArray()
var pause_at := PackedFloat64Array()
var pause_time := PackedFloat64Array()
var body_size := PackedVector3Array()
var colour := PackedColorArray()
## The lanes to take where a lane offers a choice, in order, per road user.
var route: Array = []
var route_seed := PackedInt64Array()
var reactive := PackedByteArray()
var max_accel := PackedFloat64Array()
var comfort_decel := PackedFloat64Array()
var max_decel := PackedFloat64Array()
var hard_brake := PackedFloat64Array()
var min_gap := PackedFloat64Array()
var time_headway := PackedFloat64Array()
var patience := PackedFloat64Array()
var change_time := PackedFloat64Array()
## Metres along its first lane where it starts.
var start_at := PackedFloat64Array()
## The model the traffic view draws it with; empty to let the view pick.
var model: Array = []
## The lane entity of the point it drives to and stops at, and the metres along it; 0 for none,
## when it drives its path to the end.
var goal_lane := PackedInt64Array()
var goal_at := PackedFloat64Array()
## Its car, an index into [method TrafficSpecs.all].
var spec := PackedInt64Array()
## The sideways acceleration it takes a bend at, at most, m/s².
var max_lateral := PackedFloat64Array()

# The decision columns: what thinking decided, row by row, for commit.
var d_decided := PackedByteArray()
var d_speed := PackedFloat64Array()
var d_kind := PackedInt64Array()
var d_leader := PackedInt64Array()
var d_braking_hard := PackedByteArray()
var d_committed := PackedByteArray()
var d_blocked_for := PackedFloat64Array()
var d_side_speed := PackedFloat64Array()
var d_yaw_rate := PackedFloat64Array()
var d_steer := PackedFloat64Array()
## Per row, the neighbour lanes found clear; commit checks the markings.
var d_sides: Array = []
## Per row, each [code][kind, data][/code].
var d_events: Array = []

# The routes, read while thinking: the tick's [RouteTable] columns and [LaneRules] flags, by
# lane slot, aliased here so threads read the table's own fields ([method use_routes]).
var r_slots := {}
var r_is_lane := PackedByteArray()
var r_length := PackedFloat64Array()
var r_speed_limit := PackedFloat64Array()
var r_stop_at := PackedFloat64Array()
var r_left := PackedInt64Array()
var r_right := PackedInt64Array()
var r_light := PackedInt64Array()
var r_give_ways := PackedInt32Array()
var r_curves: Array = []
var r_transforms: Array = []
var r_inverses: Array = []
var r_crossing_first := PackedInt32Array()
var r_crossing_count := PackedInt32Array()
var r_crossing_stops := PackedFloat64Array()
var r_light_red := PackedByteArray()
var r_light_amber := PackedByteArray()
var r_way_clear := PackedByteArray()
var r_crossing_busy := PackedByteArray()
var r_curvature: Array = []
## The road users' cars' specs, packed ([method TrafficSpecs.all]).
var s_specs: Array = []

var _rows := {}


## Every column of the agent component, with its default: the schema's declaration.
static func columns() -> Dictionary:
	if _columns.is_empty():
		_columns = DYNAMIC.duplicate()
		_columns.merge(CONFIG)
	return _columns


## Every column, built once ([method columns]).
static var _columns := {}


## A table to build the next tick from: its own copies of the store's dynamic columns, and the
## store's configuration columns shared, since nothing changes them after spawning.
static func copy_of(store: ComponentStore) -> AgentTable:
	var t := AgentTable.new()
	t.ids = store.ids.duplicate()
	for column: StringName in DYNAMIC:
		t.set(column, store.columns[column].duplicate())
	for column: StringName in CONFIG:
		t.set(column, store.columns[column])
	return t


## A table reading the store's columns as they are, for queries on the main thread. Its arrays
## are the world's: it must not be changed.
static func view_of(store: ComponentStore) -> AgentTable:
	var t := AgentTable.new()
	t.ids = store.ids
	for column: StringName in columns():
		t.set(column, store.columns[column])
	return t


## The world's road users as a view ([method view_of]), shared by everything that reads them in
## a tick: built again only once the store changed. Null when the world has no road users'
## component.
static func read(world: World) -> AgentTable:
	var store := world.store(Schema.AGENT)
	if store == null:
		return null
	var cached: Array = world.memo.get(&"agents", [])
	if not cached.is_empty() and cached[0] == store.version and cached[1] == store:
		return cached[2]
	var view := view_of(store)
	world.memo[&"agents"] = [store.version, store, view]
	return view


## The columns of a new road user on [param lane], from [param config] (configuration column to
## value; missing ones take their defaults), standing at the lane's start.
static func spawn_values(config: Dictionary, lane: LaneData, lanes: Dictionary) -> Dictionary:
	var values := CONFIG.duplicate()
	values.merge(config, true)
	values.merge(DYNAMIC)
	if values.spec < 0:
		values.spec = TrafficSpecs.pick(values.body_size)
	values.lane = lane.id
	values.length = lane.length
	values.progress = clampf(values.start_at, 0.0, lane.length)
	var rng := RandomNumberGenerator.new()
	rng.seed = values.route_seed
	values.rng_state = rng.state
	values.armed = values.trigger == 0
	values.jumped = true
	var one := AgentTable.new()
	for column: StringName in values:
		var array: Variant = one.get(column)
		array.append(values[column] if not values[column] is bool else (1 if values[column] else 0))
	values.upcoming = one._choose_next(0, lane)
	one.upcoming[0] = values.upcoming
	values.rng_state = one.rng_state[0]
	one._place(0, lane)
	values.position = one.position[0]
	values.facing = one.facing[0]
	return values


func size() -> int:
	return ids.size()


## The row of road user [param id], or -1.
func row_of(id: int) -> int:
	if _rows.is_empty() and not ids.is_empty():
		for i in ids.size():
			_rows[ids[i]] = i
	return _rows.get(id, -1)


## Hands the dynamic columns, now the next tick's, to [param d] for the world.
func write_to(d: Delta) -> void:
	for column: StringName in DYNAMIC:
		d.write_column(Schema.AGENT, ids, column, get(column))


func transform(i: int) -> Transform3D:
	var f := facing[i]
	return Transform3D(Basis.looking_at(f, Vector3.UP) if f.length() > 0.001 else Basis(),
		position[i])


func is_done(i: int) -> bool:
	return state[i] == State.DONE


## The speed the script asks for here: the road user's speed, capped by its lane's limit.
func script_speed(i: int, lanes: Dictionary) -> float:
	var l: LaneData = lanes.get(lane[i])
	return minf(speed[i], l.speed_limit if l else INF)


## Seconds until the road user reaches [param offset] along its path at its speed, counting the
## remaining start delay and pause; INF when it will not get there.
func time_to(i: int, offset: float, lanes: Dictionary) -> float:
	if state[i] == State.DONE or (state[i] == State.WAITING and not armed[i]):
		return INF
	var remaining := offset - progress[i]
	if remaining < 0.0:
		if not loop[i]:
			return INF
		remaining += length[i]
	var wait := 0.0
	if state[i] == State.WAITING:
		wait = maxf(start_delay[i] - clock[i], 0.0)
	elif state[i] == State.PAUSED:
		wait = maxf(pause_time[i] - paused_for[i], 0.0)
	if pause_at[i] >= 0.0 and not paused_this_lap[i] and pause_at[i] <= offset \
			and state[i] != State.PAUSED:
		wait += pause_time[i]
	return wait + remaining / maxf(script_speed(i, lanes), 0.001)


## Seconds until the road user reaches the point of its route nearest [param point]: on its
## current path, or on the lane it continues onto; INF when its route does not pass within a few
## metres of it.
func time_to_point(i: int, point: Vector3, lanes: Dictionary) -> float:
	var l: LaneData = lanes.get(lane[i])
	if l == null:
		return INF
	var where := l.project(point)
	if where.y <= 3.0 and where.x >= progress[i] - 0.5:
		return time_to(i, where.x, lanes)
	var next: LaneData = lanes.get(upcoming[i])
	if next:
		var there := next.project(point)
		if there.y <= 3.0:
			return time_to(i, length[i], lanes) \
				+ there.x / maxf(minf(speed[i], next.speed_limit), 0.001)
	return INF


## Reads [param routes] and this tick's [param flags] (from [method LaneRules.evaluate]) while
## thinking. Main thread, before thinking.
func use_routes(routes: RouteTable, flags: Array[PackedByteArray]) -> void:
	r_slots = routes.slots
	r_is_lane = routes.is_lane
	r_length = routes.length
	r_speed_limit = routes.speed_limit
	r_stop_at = routes.stop_at
	r_left = routes.left
	r_right = routes.right
	r_light = routes.light
	r_give_ways = routes.give_way_count
	r_curves = routes.curves
	r_transforms = routes.transforms
	r_inverses = routes.inverses
	r_crossing_first = routes.crossing_first
	r_crossing_count = routes.crossing_count
	r_crossing_stops = routes.crossing_stops
	r_light_red = flags[LaneRules.LIGHT_RED]
	r_light_amber = flags[LaneRules.LIGHT_AMBER]
	r_way_clear = flags[LaneRules.WAY_CLEAR]
	r_crossing_busy = flags[LaneRules.CROSSING_BUSY]
	r_curvature = routes.curvature
	s_specs = TrafficSpecs.all()


## Makes room for this tick's decisions. Main thread, before thinking.
func prepare_decisions() -> void:
	var n := ids.size()
	for array: Variant in [d_decided, d_speed, d_kind, d_leader, d_braking_hard, d_committed,
			d_blocked_for, d_side_speed, d_yaw_rate, d_steer]:
		array.resize(n)
	d_decided.fill(0)
	d_sides.resize(n)
	d_events.resize(n)


## What the road users see this tick: a [TrafficSnapshot]'s [method TrafficSnapshot.arrays], set
## on the main thread before they think ([method see]).
var seen: Array = []


## Gives the table what road users see this tick. Main thread, before they think.
func see(snapshot: TrafficSnapshot) -> void:
	seen = snapshot.arrays()


## Decides row [param i]'s speed and reactions from what it sees ([member seen]). Any thread: it
## reads the table's own arrays, writes only row [param i] of the decision columns, and creates no
## object of a script class. In four parts: what is ahead, the speed it calls for,
## whether that is hard braking, and, when stuck, the neighbour lanes it could move into.
func think(i: int, dt: float) -> void:
	if state[i] == State.MOVING and crashed[i] and not pedestrian[i]:
		_drift(i, dt)
		return
	if state[i] != State.MOVING or not reactive[i]:
		return
	var slot: int = r_slots.get(lane[i], -1)
	if slot < 0:
		return
	d_decided[i] = 1
	d_committed[i] = committed[i]
	var events := []
	var target := minf(speed[i], r_speed_limit[slot])
	var drives := not pedestrian[i]
	if drives:
		target = minf(target, _bend_speed(i, slot))
	var ahead := PackedFloat64Array([0.0, 0.0, INF, 0.0, 0.0])
	var rule := _ahead(i, slot, target, ahead)
	var kind := _decide_speed(i, ahead, rule, target, dt)
	if drives:
		_drive(i, slot, kind, dt)
	var body := int(ahead[AHEAD_ENTITY])
	_decide_braking(i, ahead, events)
	if kind != reaction[i]:
		events.append([&"reacted", {kind = &"resumed" if kind == Kind.NONE else KIND_NAMES[kind],
			cause = body}])
	d_kind[i] = kind
	d_leader[i] = body
	var blocked := kind == Kind.STOPPED and body != 0 and ahead[AHEAD_ROAD_USER] < 0.5
	d_blocked_for[i] = blocked_for[i] + dt if blocked else 0.0
	d_sides[i] = _clear_sides(i, slot, target, dt)
	d_events[i] = events


## What holds row [param i] back ahead on lane [param slot]: the sensor's nearest body, or a lane
## rule's stop line when nearer. Writes it into [param ahead] as found, entity (0 for a stop
## line), gap, speed along the way, and road user, at the [code]AHEAD_*[/code] indices; returns the
## rule when a stop line is what holds it, else [constant Kind.NONE].
func _ahead(i: int, slot: int, target: float, ahead: PackedFloat64Array) -> Kind:
	TrafficSensor.sense(seen, _ahead_points(i, slot, target), body_size[i].x * 0.45, ids[i],
		ahead)
	var rule_gap := PackedFloat64Array([INF])
	var rule := _rule_kind(i, slot, rule_gap)
	if rule == Kind.NONE:
		return rule
	if ahead[AHEAD_FOUND] < 0.5 or rule_gap[0] < ahead[AHEAD_GAP]:
		ahead[AHEAD_FOUND] = 1.0
		ahead[AHEAD_ENTITY] = 0.0
		ahead[AHEAD_GAP] = rule_gap[0]
		ahead[AHEAD_SPEED] = 0.0
		ahead[AHEAD_ROAD_USER] = 0.0
		return rule
	return Kind.NONE


## Row [param i]'s speed for the next tick behind [param ahead], into its decision, and the
## reaction it amounts to.
func _decide_speed(i: int, ahead: PackedFloat64Array, rule: Kind, target: float,
		dt: float) -> Kind:
	var found := ahead[AHEAD_FOUND] > 0.5
	var gap := ahead[AHEAD_GAP]
	var ahead_speed := ahead[AHEAD_SPEED]
	var v := current_speed[i]
	var accel := max_accel[i] if v < target else 0.0
	var kind := Kind.NONE
	var reacting := reaction[i] != Kind.NONE
	# Once reacting, the model keeps control until the road user is back at its scripted speed
	# with nothing holding it back, so it neither creeps up on a leader nor lets go too early.
	if found and (reacting or _forced(i, gap, ahead_speed, v)):
		var model := _idm(i, v, gap, ahead_speed, target)
		if not (reacting and v >= target - 0.01 and model >= 0.0):
			accel = model
			kind = Kind.STOPPED if v + accel * dt < 0.3 else Kind.FOLLOWING
			if rule != Kind.NONE:
				kind = rule
	var next := clampf(v + accel * dt, 0.0, target)
	if found and (gap <= 0.05 or (v + accel * dt < 0.3 and kind != Kind.NONE
			and kind != Kind.FOLLOWING and absf(ahead_speed) < 0.1)):
		# Behind something standing still the road user stands still too, rather than creeping
		# up at the model's crawl, and it never moves into what it already touches.
		next = 0.0
		if kind == Kind.NONE or kind == Kind.FOLLOWING:
			kind = Kind.STOPPED
	d_speed[i] = next
	return kind


## Whether stopping short of the body [param ahead] takes hard braking, into row [param i]'s
## decision, with a [code]&"forced_to_brake"[/code] event in [param events] when it starts to.
func _decide_braking(i: int, ahead: PackedFloat64Array, events: Array) -> void:
	var body := int(ahead[AHEAD_ENTITY])
	var needed := _needed_decel(i, current_speed[i], ahead[AHEAD_GAP], ahead[AHEAD_SPEED]) \
		if body else 0.0
	var hard := braking_hard[i] == 1
	if needed > hard_brake[i] and not hard:
		hard = true
		events.append([&"forced_to_brake", {cause = body, deceleration = needed}])
	elif needed <= hard_brake[i]:
		hard = false
	d_braking_hard[i] = 1 if hard else 0


## The neighbour lanes of [param slot] row [param i] could move into: clear ones, once it has been
## blocked by something that is not traffic for its patience and is not mid lane change.
func _clear_sides(i: int, slot: int, target: float, dt: float) -> PackedInt64Array:
	var sides := PackedInt64Array()
	if d_blocked_for[i] < patience[i] or maxf(shift_left[i] - dt, 0.0) > 0.0 \
			or not r_is_lane[slot]:
		return sides
	for side in [r_left[slot], r_right[slot]]:
		var other: int = r_slots.get(side, -1) if side else -1
		if other >= 0 and _neighbour_clear(i, other, target):
			sides.append(side)
	return sides


## Moves row [param i] on by [param dt] seconds, applying its decision when it thought: the
## script's timers, its progress along the path, lane changes. [param armed_now] is whether its
## trigger zone holds the car; [param markings] the scenario's [MarkingIndex], or null. Returns the
## tick's events as [code][kind, data][/code] pairs. Main thread.
func commit(i: int, lanes: Dictionary, markings: MarkingIndex, armed_now: bool,
		dt: float) -> Array:
	var events := []
	jumped[i] = 0
	match state[i]:
		State.WAITING:
			if armed_now:
				armed[i] = 1
			if armed[i]:
				clock[i] += dt
				if clock[i] >= start_delay[i]:
					state[i] = State.MOVING
					current_speed[i] = script_speed(i, lanes)
					events.append([&"agent_started", {}])
		State.PAUSED:
			paused_for[i] += dt
			if paused_for[i] >= pause_time[i]:
				state[i] = State.MOVING
		State.MOVING:
			if crashed[i] and d_decided[i]:
				current_speed[i] = d_speed[i]
				reaction[i] = d_kind[i]
			elif not reactive[i] or not d_decided[i]:
				current_speed[i] = script_speed(i, lanes)
			else:
				current_speed[i] = d_speed[i]
				leader[i] = d_leader[i]
				braking_hard[i] = d_braking_hard[i]
				committed[i] = d_committed[i]
				blocked_for[i] = d_blocked_for[i]
				reaction[i] = d_kind[i]
				events.append_array(d_events[i])
				shift_left[i] = maxf(shift_left[i] - dt, 0.0)
				for side: int in d_sides[i]:
					var target: LaneData = lanes.get(side)
					if target and _markings_allow(i, target, markings):
						_move_to(i, target, d_leader[i], events)
						break
			if d_decided[i] and not pedestrian[i] and (reactive[i] or crashed[i]):
				side_speed[i] = d_side_speed[i]
				yaw_rate[i] = d_yaw_rate[i]
				steer[i] = d_steer[i]
				_advance(i, _along_path(i, dt), lanes, events)
			else:
				_advance(i, current_speed[i] * dt, lanes, events)
	return events


func _advance(i: int, step: float, lanes: Dictionary, events: Array) -> void:
	progress[i] += step
	if goal_lane[i] != 0 and lane[i] == goal_lane[i] and progress[i] >= goal_at[i]:
		progress[i] = goal_at[i]
		state[i] = State.DONE
		current_speed[i] = 0.0
		events.append([&"agent_finished", {reached = true}])
		_place(i, lanes.get(lane[i]))
		return
	if pause_at[i] >= 0.0 and not paused_this_lap[i] and progress[i] >= pause_at[i]:
		progress[i] = pause_at[i]
		paused_this_lap[i] = 1
		paused_for[i] = 0.0
		state[i] = State.PAUSED
	elif progress[i] >= length[i] and upcoming[i]:
		progress[i] -= length[i]
		_enter(i, lanes.get(upcoming[i]))
	elif progress[i] >= length[i]:
		if loop[i]:
			progress[i] = fmod(progress[i], length[i])
			paused_this_lap[i] = 0
			# Jumped back to the path's start: drawn there, not sliding back across the world.
			jumped[i] = 1
			lateral[i] = 0.0
			heading[i] = 0.0
			side_speed[i] = 0.0
			yaw_rate[i] = 0.0
		else:
			progress[i] = length[i]
			state[i] = State.DONE
			events.append([&"agent_finished", {}])
	_place(i, lanes.get(lane[i]))


## Places row [param i] on [param l]: on the curve at its progress, facing along it, eased across
## during a lane change.
func _place(i: int, l: LaneData) -> void:
	if l == null or l.curve == null:
		return
	var curve := l.curve
	var total := length[i] if length[i] > 0.0 else l.length
	var offset := progress[i]
	var here := l.transform * curve.sample_baked(offset)
	var ahead := l.transform * curve.sample_baked(minf(offset + 0.5, total))
	var behind := l.transform * curve.sample_baked(maxf(offset - 0.5, 0.0))
	var tangent := ahead - behind
	var run := tangent.length()
	var slope := tangent.y / run if run > 0.001 else 0.0
	tangent.y = 0.0
	if tangent.length() > 0.001:
		tangent = tangent.normalized()
		# Off the path by its lateral offset, at its heading's angle to it.
		here += Vector3.UP.cross(tangent) * lateral[i]
		facing[i] = tangent.rotated(Vector3.UP, heading[i])
		# The slope it climbs is the lane's along its facing, the heading's cosine of it.
		slope *= cos(heading[i])
	grade[i] = slope
	position[i] = here


func _enter(i: int, l: LaneData) -> void:
	lane[i] = l.id
	length[i] = l.length
	committed[i] = 0
	upcoming[i] = _choose_next(i, l)


func _choose_next(i: int, l: LaneData) -> int:
	if l == null or not l.is_lane or l.next.is_empty() or l.id == goal_lane[i]:
		return 0
	for wanted: int in route[i]:
		if l.next.has(wanted):
			return wanted
	var rng := RandomNumberGenerator.new()
	rng.state = rng_state[i]
	var pick := l.next[rng.randi_range(0, l.next.size() - 1)]
	rng_state[i] = rng.state
	return pick


func _move_to(i: int, target: LaneData, blocker: int, events: Array) -> void:
	var from := position[i]
	var at := target.project(from).x
	_enter(i, target)
	progress[i] = at
	var offset := from - target.point_at(at)
	offset.y = 0.0
	var along := target.ground_tangent(at)
	# Where it is now, off the new lane: it steers across to it.
	lateral[i] = offset.dot(Vector3.UP.cross(along.normalized())) if along.length() > 0.001 \
		else 0.0
	shift[i] = Vector3.ZERO
	shift_left[i] = change_time[i]
	blocked_for[i] = 0.0
	reaction[i] = Kind.CHANGING_LANE
	events.append([&"reacted", {kind = &"changing_lane", cause = blocker}])


## Whether the markings let row [param i] move across into [param target]: no solid line or kerb
## lies on the way.
func _markings_allow(i: int, target: LaneData, markings: MarkingIndex) -> bool:
	if markings == null:
		return true
	var from := position[i]
	var at := target.project(from).x
	var across := target.point_at(at + body_size[i].z)
	for hit in markings.crossings(from, across):
		if hit.kind == RoadMarking.Kind.SOLID or hit.kind == RoadMarking.Kind.DOUBLE_SOLID \
				or hit.kind == RoadMarking.Kind.KERB:
			return false
	return true


## Whether something [param gap] metres ahead, moving at [param ahead_speed], forces a reaction at
## speed [param v]: it is within the gap kept at a reaction's headway, or closing so fast that
## keeping the script would need braking.
func _forced(i: int, gap: float, ahead_speed: float, v: float) -> bool:
	if gap <= min_gap[i] + v * 0.5:
		return true
	var closing := v - ahead_speed
	if closing <= 0.0:
		return false
	return closing * closing / (2.0 * maxf(gap - min_gap[i], 0.01)) > 0.5


## The deceleration that stopping short of what is ahead, keeping the minimum gap, needs at speed
## [param v]; 0 when it is not closing in.
func _needed_decel(i: int, v: float, gap: float, ahead_speed: float) -> float:
	var closing := v - ahead_speed
	if closing <= 0.0:
		return 0.0
	return closing * closing / (2.0 * maxf(gap - min_gap[i], 0.1))


## The Intelligent Driver Model's acceleration behind what is ahead, towards the scripted speed.
func _idm(i: int, v: float, gap: float, ahead_speed: float, target: float) -> float:
	var closing := v - ahead_speed
	var accel := max_accel[i]
	var wanted := min_gap[i] + maxf(0.0, v * time_headway[i]
		+ v * closing / (2.0 * sqrt(accel * comfort_decel[i])))
	var g := maxf(gap, 0.05)
	var free := 1.0 - pow(v / maxf(target, 0.1), 4.0)
	return maxf(accel * (free - (wanted / g) * (wanted / g)), -max_decel[i])


## The point of lane [param slot] at [param offset] along it.
func _point_at(slot: int, offset: float) -> Vector3:
	var curve: Curve3D = r_curves[slot]
	var t: Transform3D = r_transforms[slot]
	return t * curve.sample_baked(clampf(offset, 0.0, r_length[slot]))


## The distance along lane [param slot] of its point nearest [param point].
func _offset_on(slot: int, point: Vector3) -> float:
	var curve: Curve3D = r_curves[slot]
	var inv: Transform3D = r_inverses[slot]
	return curve.get_closest_offset(inv * point)


## The path ahead of row [param i]'s front on lane [param slot], as the sensor sweeps it.
func _ahead_points(i: int, slot: int, target: float) -> PackedVector3Array:
	var points := PackedVector3Array()
	var front := progress[i] + body_size[i].z * 0.5
	var look := _look_ahead(target)
	var next := _next_slot(i)
	var total := r_length[slot]
	for k in TrafficSensor.SEGMENTS + 1:
		var offset := front + look * k / TrafficSensor.SEGMENTS
		if offset > total and next >= 0:
			points.append(_point_at(next, offset - total))
		else:
			if loop[i] and total > 0.0:
				offset = fposmod(offset, total)
			points.append(_point_at(slot, offset))
	return points


## The lane rule holding row [param i] back now on lane [param slot], with its stop line's gap in
## [code]rule_gap[0][/code]; [constant Kind.NONE] when no rule applies. May commit the row to the
## stop line.
func _rule_kind(i: int, slot: int, rule_gap: PackedFloat64Array) -> Kind:
	if not r_is_lane[slot]:
		return Kind.NONE
	var front := progress[i] + body_size[i].z * 0.5
	# The model keeps the minimum gap to a leader; a stop line is kept at about a metre instead.
	var slack := min_gap[i] - 1.0
	var first := r_crossing_first[slot]
	for k in range(first, first + r_crossing_count[slot]):
		var crossing_gap := r_crossing_stops[k] - front
		if crossing_gap > -0.5 and r_crossing_busy[k]:
			rule_gap[0] = crossing_gap + slack
			return Kind.YIELDING
	var gap := r_stop_at[slot] - front
	if gap < -0.5 or d_committed[i]:
		return Kind.NONE
	var v := current_speed[i]
	if r_light[slot] and (r_light_red[slot] or r_light_amber[slot]):
		# Stop only where stopping is still possible; past that point, go through.
		if gap >= v * v / (2.0 * max_decel[i]) or v < 0.5:
			rule_gap[0] = gap + slack
			return Kind.WAITING_LIGHT
		d_committed[i] = 1
		return Kind.NONE
	if r_give_ways[slot] > 0:
		if not r_way_clear[slot]:
			rule_gap[0] = gap + slack
			return Kind.YIELDING
		if gap < 1.5:
			d_committed[i] = 1
	return Kind.NONE


## Whether lane [param slot], a neighbour, is clear from a little behind row [param i] to its
## look-ahead.
func _neighbour_clear(i: int, slot: int, target: float) -> bool:
	var at := _offset_on(slot, position[i])
	var behind := 15.0
	var reach := behind + _look_ahead(target) + body_size[i].z
	var points := PackedVector3Array()
	for k in TrafficSensor.SEGMENTS + 1:
		points.append(_point_at(slot, at - behind + reach * k / TrafficSensor.SEGMENTS))
	var hit := PackedFloat64Array([0.0, 0.0, INF, 0.0, 0.0])
	return not TrafficSensor.sense(seen, points, body_size[i].x * 0.45, ids[i], hit)


## The speed row [param i] takes the bends ahead on lane [param slot] at: through each, no faster
## than turns it at its [member max_lateral], slowing to it from here at its comfortable
## deceleration.
func _bend_speed(i: int, slot: int) -> float:
	var v := current_speed[i]
	var comfort := comfort_decel[i]
	var look := v * v / (2.0 * comfort) + 10.0
	var here: PackedFloat64Array = r_curvature[slot]
	var next := _next_slot(i)
	var then: PackedFloat64Array = r_curvature[next] if next >= 0 else PackedFloat64Array()
	var count := here.size()
	var start := int(progress[i] / RouteTable.CURVATURE_STEP)
	var steps := int(look / RouteTable.CURVATURE_STEP)
	var most := 0.0
	var best := INF
	# Every third sample: a bend's curvature changes over metres, not over one.
	for k in range(0, steps + 1, 3):
		var at := start + k
		var c := 0.0
		if at < count:
			c = here[at]
		elif not then.is_empty():
			c = then[mini(at - count, then.size() - 1)]
		elif loop[i] and count > 0:
			c = here[at % count]
		c = absf(c)
		if c > 0.002 and c > most * 0.5:
			most = maxf(most, c)
			var through := max_lateral[i] / c
			best = minf(best, sqrt(through + 2.0 * comfort * k * RouteTable.CURVATURE_STEP))
	return best


## The curvature of row [param i]'s path [param ahead] metres on from it, on lane [param slot] and
## the lane it continues onto.
func _curvature_ahead(i: int, slot: int, ahead: float) -> float:
	var offset := progress[i] + ahead
	var total := r_length[slot]
	if offset > total:
		var next := _next_slot(i)
		if next < 0:
			if not loop[i] or total <= 0.0:
				return 0.0
			offset = fposmod(offset, total)
		else:
			slot = next
			offset -= total
	return _curvature_at(slot, offset)


## Lane [param slot]'s curvature at [param offset] metres along it, from its samples; nought for a
## lane with none.
func _curvature_at(slot: int, offset: float) -> float:
	var samples: PackedFloat64Array = r_curvature[slot]
	if samples.is_empty():
		return 0.0
	return samples[clampi(int(offset / RouteTable.CURVATURE_STEP), 0, samples.size() - 1)]


## The lane row [param i] continues onto, as a route slot; -1 when it has none.
func _next_slot(i: int) -> int:
	return r_slots.get(upcoming[i], -1) if upcoming[i] else -1


## How far ahead row [param i] looks at [param target] m/s, metres: three seconds and five metres.
static func _look_ahead(target: float) -> float:
	return target * 3.0 + 5.0


## Drives row [param i]'s car one step toward the speed it decided ([member d_speed]): steers to
## keep its lane, or across to it during a lane change, and steps the [PlanarVehicle]. Writes its
## speeds and steering into its decision. Any thread.
func _drive(i: int, slot: int, kind: Kind, dt: float) -> void:
	var car: PackedFloat64Array = s_specs[spec[i]]
	var v := current_speed[i]
	var wanted := (d_speed[i] - v) / dt
	if kind == Kind.NONE:
		# Playing its script, it eases down to a lower limit rather than braking hard.
		wanted = maxf(wanted, -comfort_decel[i])
	var bend := _curvature_ahead(i, slot, v * 0.3)
	var aim := atan(-lateral[i] * 2.0 / maxf(change_time[i], 0.5) / maxf(v, 2.0))
	aim = clampf(aim, -0.15, 0.15)
	var gain := car[CarSpec.WHEELBASE] / (maxf(v, 1.0) * 0.35)
	var lock := car[CarSpec.STEER_LOCK]
	var angle := clampf(PlanarVehicle.steer_for(car, bend, v) + gain * (aim - heading[i]),
		-lock, lock)
	var next := PlanarVehicle.step(car, Vector3(v, side_speed[i], yaw_rate[i]), angle, wanted,
		1.0, dt, grade[i])
	d_speed[i] = next.x
	d_side_speed[i] = next.y
	d_yaw_rate[i] = next.z
	d_steer[i] = angle


## Moves row [param i] across and around its path for [param dt] seconds as its car's speeds take
## it, and returns how far along the path that is. Main thread, in commit.
func _along_path(i: int, dt: float) -> float:
	var slot: int = r_slots.get(lane[i], -1)
	var k := _curvature_at(slot, progress[i]) if slot >= 0 else 0.0
	var vx := current_speed[i]
	var vy := side_speed[i]
	var psi := heading[i]
	var along := (vx * cos(psi) - vy * sin(psi)) / maxf(1.0 - k * lateral[i], 0.2)
	lateral[i] += (vx * sin(psi) + vy * cos(psi)) * dt
	heading[i] = wrapf(psi + (yaw_rate[i] - k * along) * dt, -PI, PI)
	return maxf(along * dt, 0.0)


## A crashed row [param i]: no longer driving its lane, it brakes to a halt with the wheels
## straight, sliding and turning as the knock left it. Any thread.
func _drift(i: int, dt: float) -> void:
	var car: PackedFloat64Array = s_specs[spec[i]]
	var next := PlanarVehicle.step(car, Vector3(current_speed[i], side_speed[i], yaw_rate[i]),
		0.0, -6.0, 1.0, dt, grade[i])
	if next.x <= 0.0 and absf(next.y) < 0.2:
		next = Vector3.ZERO
	d_decided[i] = 1
	d_speed[i] = next.x
	d_side_speed[i] = next.y
	d_yaw_rate[i] = next.z
	d_steer[i] = 0.0
	d_kind[i] = Kind.STOPPED if next.x < 0.3 else reaction[i]
	d_leader[i] = 0
	d_braking_hard[i] = 0
	d_committed[i] = committed[i]
	d_blocked_for[i] = 0.0
	d_sides[i] = PackedInt64Array()
	d_events[i] = []
