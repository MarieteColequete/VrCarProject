class_name TrafficPipeline
extends PipelinedSystem
## Every road user's tick, pipelined across physics ticks so their thinking runs alongside the rest
## of the frame (the player's car, rendering) instead of adding to it.
##
## [method begin], once a tick is applied, copies the road users' columns into an [AgentTable],
## takes a [TrafficSnapshot] of the world, and has every row decide its next speed and reactions
## ([method AgentTable.think]), in parallel through the [WorkerThreadPool] when there are enough of
## them, each task a run of rows. [method finish], first in the next tick, waits for the decisions,
## commits every row in row order ([method AgentTable.commit]), and returns the table's columns
## whole with the tick's events. Road users therefore react one tick after they see, and the
## outcome is the same whatever the threads do: traffic stays reproducible.

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

var _table: AgentTable
var _armed := PackedByteArray()
var _snapshot: TrafficSnapshot
var _lanes := {}
var _markings: MarkingIndex
var _dt := 0.0
var _tasks := 1
var _task := -1


func begin(world: World, dt: float) -> void:
	var started := Time.get_ticks_usec()
	var store := world.store(Schema.AGENT)
	if store == null or store.size() == 0:
		count = 0
		think_usec = 0
		return
	_dt = dt
	_lanes = world.resources.get(Schema.LANES, {})
	_markings = world.resources.get(Schema.MARKINGS)
	_table = AgentTable.copy_of(store)
	_table.prepare_decisions()
	count = _table.size()
	_armed = PackedByteArray()
	_armed.resize(count)
	var zones := world.store(Schema.ZONE)
	for i in count:
		var zone := _table.trigger[i]
		_armed[i] = 1 if zone != 0 and zones and zones.has(zone) \
			and zones.get_value(zone, &"inside") else 0
	_snapshot = snapshot_of(world, _table, _lanes)
	if parallel and count >= PARALLEL_FROM:
		# A task per run of rows rather than one per road user: enough to use the cores without the
		# threads queuing on each other.
		_tasks = mini(mini(OS.get_processor_count(), MAX_TASKS), ceili(count / float(PARALLEL_FROM)))
		_task = WorkerThreadPool.add_group_task(_think_run, _tasks, _tasks, true,
			"Road users think")
	else:
		_tasks = 1
		_think_run(0)
	think_usec = Time.get_ticks_usec() - started


func finish() -> Delta:
	var started := Time.get_ticks_usec()
	_wait()
	wait_usec = Time.get_ticks_usec() - started
	if _table == null:
		commit_usec = wait_usec
		return null
	var d := Delta.new()
	var table := _table
	for i in table.size():
		for event: Array in table.commit(i, _lanes, _markings, _armed[i] == 1, _dt):
			d.emit(WorldEvent.new(event[0], table.ids[i], event[1]))
	table.write_to(d)
	_table = null
	_snapshot = null
	commit_usec = Time.get_ticks_usec() - started
	return d


## The world as road users see it now: every road user, the player's car, every obstacle, and
## every lane they drive with its rules evaluated. Main thread.
static func snapshot_of(world: World, table: AgentTable, lanes: Dictionary) -> TrafficSnapshot:
	var snapshot := TrafficSnapshot.new()
	var car := CarState.read(world)
	for i in table.size():
		var size := table.body_size[i]
		var f := table.facing[i]
		var flat := Vector2(f.x, f.z).normalized()
		var at := table.position[i]
		snapshot.add(table.ids[i], Vector2(at.x, at.z), flat, size.z * 0.5, size.x * 0.5,
			flat * table.current_speed[i], true)
		for lane_id in table.lanes_in_use(i, lanes):
			if lane_id and not snapshot.routes.has(lane_id) and lanes.has(lane_id):
				snapshot.routes[lane_id] = LaneRules.route_of(lanes[lane_id], world, table, car,
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


## Thinks the [param task]-th run of rows. The table and snapshot are read through locals, once.
func _think_run(task: int) -> void:
	var table := _table
	var snapshot := _snapshot
	var dt := _dt
	var n := table.size()
	for i in range(n * task / _tasks, n * (task + 1) / _tasks):
		table.think(i, snapshot, dt)


func _wait() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_task)
		_task = -1
