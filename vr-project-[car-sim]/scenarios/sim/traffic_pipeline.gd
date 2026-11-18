class_name TrafficPipeline
extends PipelinedSystem
## Every road user's tick, pipelined across physics ticks so their thinking runs alongside the rest
## of the frame (the player's car, rendering) instead of adding to it.
##
## [method begin], once a tick is applied, takes a [TrafficSnapshot] of the world, loads each road
## user's [AgentThinker] with its state, and has them decide their next speed and reactions, in
## parallel through the [WorkerThreadPool] when there are enough of them. [method finish], first in
## the next tick, waits for the decisions and commits them in entity order
## ([method AgentLogic.commit]), returning the new states and events. Road users therefore react
## one tick after they see. Decisions read only their own copies and the snapshot, and are applied
## in order, so the outcome is the same whatever the threads do: traffic stays reproducible.

## Below this many road users, thinking runs on the main thread, where it costs less than handing
## it to threads.
const PARALLEL_FROM := 16
## The most tasks thinking is split into.
const MAX_TASKS := 8

## Thinks on worker threads; off, on the main thread, with the same results.
var parallel := true
## Microseconds the main thread spent in the last tick taking the snapshot and starting the
## thinking, and waiting for the thinking and committing it.
var think_usec := 0
var commit_usec := 0
## Of [member commit_usec], the microseconds spent waiting for threads still thinking.
var wait_usec := 0
## How many road users the last tick ran.
var count := 0

var _ids := PackedInt64Array()
var _states: Array = []
var _thinkers: Array = []
# Road user entity to its thinker, kept across ticks.
var _thinker_of := {}
var _armed := PackedByteArray()
var _snapshot: TrafficSnapshot
var _lanes := {}
var _markings: MarkingIndex
var _dt := 0.0
var _task := -1


func begin(world: World, dt: float) -> void:
	var started := Time.get_ticks_usec()
	var store := world.store(Schema.AGENT)
	if store == null or store.size() == 0:
		count = 0
		think_usec = 0
		return
	_dt = dt
	_lanes = world.resources.get(&"lanes", {})
	_markings = world.resources.get(Schema.MARKINGS)
	_ids = store.sorted_ids()
	count = _ids.size()
	_states = []
	_thinkers = []
	_armed = PackedByteArray()
	var agents := {}
	for id in _ids:
		var s: AgentState = store.get_value(id, &"state")
		_states.append(s)
		agents[id] = s
		var thinker: AgentThinker = _thinker_of.get(id)
		if thinker == null:
			thinker = AgentThinker.new()
			_thinker_of[id] = thinker
		thinker.load(id, s)
		_thinkers.append(thinker)
		var trigger := s.config.trigger
		_armed.append(1 if trigger != 0 and world.has(Schema.ZONE, trigger)
			and world.get_value(Schema.ZONE, trigger, &"inside") else 0)
	_snapshot = snapshot_of(world, agents, _ids, _lanes)
	if parallel and count >= PARALLEL_FROM:
		# A task per batch of road users rather than one per thread available: enough to use the
		# cores without the threads queuing on each other.
		var tasks := mini(mini(OS.get_processor_count(), MAX_TASKS), ceili(count / float(PARALLEL_FROM)))
		_task = WorkerThreadPool.add_group_task(_think, count, tasks, true, "Road users think")
	else:
		for i in count:
			_think(i)
	think_usec = Time.get_ticks_usec() - started


func finish() -> Delta:
	var started := Time.get_ticks_usec()
	_wait()
	wait_usec = Time.get_ticks_usec() - started
	if _ids.is_empty():
		commit_usec = wait_usec
		return null
	var d := Delta.new()
	for i in _ids.size():
		var thinker: AgentThinker = _thinkers[i]
		var next := AgentState.new()
		var events := AgentLogic.commit(_states[i], _ids[i], thinker if thinker.decided else null,
			_lanes, _markings, _armed[i] == 1, _dt, next)
		d.write(Schema.AGENT, _ids[i], &"state", next)
		for event: Array in events:
			d.emit(WorldEvent.new(event[0], _ids[i], event[1]))
	_ids = PackedInt64Array()
	_states = []
	_thinkers = []
	_snapshot = null
	commit_usec = Time.get_ticks_usec() - started
	return d


## The world as road users see it now: every road user, the player's car, every obstacle, and
## every lane they drive with its rules evaluated. Main thread.
static func snapshot_of(world: World, agents: Dictionary, ids: PackedInt64Array,
		lanes: Dictionary) -> TrafficSnapshot:
	var snapshot := TrafficSnapshot.new()
	var car := CarState.read(world)
	for id in ids:
		var s: AgentState = agents[id]
		var size := s.config.body_size
		var facing := s.forward()
		var flat := Vector2(facing.x, facing.z)
		var at := s.position()
		snapshot.add(id, Vector2(at.x, at.z), flat, size.z * 0.5, size.x * 0.5,
			flat * s.current_speed, true)
		for lane_id in AgentLogic.lanes_in_use(s, lanes):
			if lane_id and not snapshot.routes.has(lane_id) and lanes.has(lane_id):
				snapshot.routes[lane_id] = LaneRules.route_of(lanes[lane_id], world, agents, car,
					lanes)
	if car:
		snapshot.add_box(car.entity, car.transform, car.hull_size, car.velocity, false)
	var obstacles := world.store(Schema.OBSTACLE)
	if obstacles:
		for id in obstacles.sorted_ids():
			snapshot.add_box(id, obstacles.get_value(id, &"transform"),
				obstacles.get_value(id, &"size"), Vector3.ZERO, false)
	snapshot.seal()
	return snapshot


func _think(index: int) -> void:
	_thinkers[index].think(_snapshot, _dt)


func _wait() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_task)
		_task = -1
