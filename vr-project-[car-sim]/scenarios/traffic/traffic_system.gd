class_name TrafficSystem
extends Node
## Runs every road user of the scene tree on worker threads, pipelined across physics ticks, so
## their thinking runs alongside the main thread's own work (the player's car, input, checks, the
## physics step, and rendering) instead of adding to it.
##
## First in each tick, on the main thread: commit, then think. Commit applies the decisions
## thought during the previous tick, in a fixed order, moving the road users and emitting their
## signals; it normally finds them long finished. Think takes a [TrafficSnapshot] of the world as
## it now stands and has every road user decide its next speed and reactions from it, in parallel
## through the [WorkerThreadPool], while the rest of the tick goes on. Road users therefore react
## one physics tick later than they see. Decisions read only their snapshot and are applied in
## order, so the outcome is the same whatever the threads do: traffic stays reproducible.
##
## One system serves a scene tree; [method of] creates it on first use, so scenes need no setup.

const NODE_NAME := &"TrafficSystem"
const META_KEY := &"traffic_system"
## Below this many road users, thinking runs on the main thread, where it costs less than handing
## it to threads.
const PARALLEL_FROM := 16
## The most tasks thinking is split into. Measured on 200 road users, thinking scales to about
## eight tasks; past that, threads spend their time on the few objects they share.
const MAX_TASKS := 8

## Thinks on worker threads; off, on the main thread, with the same results.
var parallel := true
## Microseconds the main thread spent in the last tick taking the snapshot and starting the
## thinking, and waiting for the previous thinking and committing it.
var think_usec := 0
var commit_usec := 0
## Of [member commit_usec], the microseconds spent waiting for threads still thinking: zero when
## the thinking fitted into the rest of the previous tick.
var wait_usec := 0

var _agents: Array[ScriptedAgent] = []
var _thinking: Array[ScriptedAgent] = []
var _snapshot: TrafficSnapshot
var _delta := 0.0
var _task := -1
var _statics: Array[TrafficSnapshot.Box] = []
var _statics_dirty := true


## The scene tree's traffic system, created and added to the root on first use.
static func of(node: Node) -> TrafficSystem:
	var root := node.get_tree().root
	if root.has_meta(META_KEY):
		var existing: TrafficSystem = root.get_meta(META_KEY)
		if is_instance_valid(existing):
			return existing
	var system := TrafficSystem.new()
	system.name = NODE_NAME
	root.set_meta(META_KEY, system)
	# Added at once, so a road user's first tick is not lost; deferred only while the root is
	# still being set up.
	if root.is_node_ready():
		root.add_child(system)
	else:
		root.add_child.call_deferred(system)
	return system


func _ready() -> void:
	process_physics_priority = -1000
	get_tree().node_added.connect(_on_tree_changed)
	get_tree().node_removed.connect(_on_tree_changed)


func add(agent: ScriptedAgent) -> void:
	if not _agents.has(agent):
		_agents.append(agent)


func remove(agent: ScriptedAgent) -> void:
	# A road user leaving may be freed next; no thread may still be thinking with it.
	_wait()
	_agents.erase(agent)
	_thinking.erase(agent)


## How many road users the system runs.
func count() -> int:
	return _agents.size()


func _physics_process(delta: float) -> void:
	_commit()
	var started := Time.get_ticks_usec()
	_thinking = _agents.duplicate()
	if _thinking.is_empty():
		think_usec = 0
		return
	_delta = delta
	_snapshot = _take_snapshot()
	if parallel and _thinking.size() >= PARALLEL_FROM:
		# A task per batch of road users rather than one per thread available: enough to use the
		# cores without the threads queuing on each other.
		var tasks := mini(mini(OS.get_processor_count(), MAX_TASKS),
			ceili(_thinking.size() / float(PARALLEL_FROM)))
		_task = WorkerThreadPool.add_group_task(_think, _thinking.size(), tasks, true,
			"Road users think")
	else:
		for i in _thinking.size():
			_think(i)
	think_usec = Time.get_ticks_usec() - started


func _think(index: int) -> void:
	_thinking[index].think(_snapshot, _delta)


func _wait() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_group_task_completion(_task)
		_task = -1


func _commit() -> void:
	var started := Time.get_ticks_usec()
	_wait()
	wait_usec = Time.get_ticks_usec() - started
	# Every road user commits, in the order they joined: those that thought apply their decision,
	# and those added since the last snapshot just play their script for this tick.
	for agent in _agents.duplicate():
		if is_instance_valid(agent) and agent.is_inside_tree():
			agent.commit(get_physics_process_delta_time())
	_thinking.clear()
	_snapshot = null
	commit_usec = Time.get_ticks_usec() - started


## The world as road users see it now: every road user, every vehicle with a probe, every static
## obstacle, and every path they drive with its rules evaluated.
func _take_snapshot() -> TrafficSnapshot:
	var snapshot := TrafficSnapshot.new()
	for agent in _thinking:
		if is_instance_valid(agent) and agent.is_inside_tree():
			var origin := agent.global_position
			var facing := agent.forward()
			var flat := Vector2(facing.x, facing.z)
			snapshot.add(agent, Vector2(origin.x, origin.z), flat, agent.body_size.z * 0.5,
				agent.body_size.x * 0.5, flat * agent.current_speed, true)
			for path in agent.paths_in_use():
				if path and not snapshot.routes.has(path):
					snapshot.routes[path] = TrafficSnapshot.route_of(path)
	for node in get_tree().get_nodes_in_group(Layers.GROUP_VEHICLE):
		var probe := node as VehicleProbe
		if probe:
			snapshot.add_box(TrafficSnapshot.box_at(probe.get_parent(), probe.global_transform,
				probe.hull_size.z, probe.hull_size.x, probe.velocity))
	if _statics_dirty:
		_statics_dirty = false
		_collect_statics()
	for box in _statics:
		snapshot.add_box(box)
	snapshot.seal()
	return snapshot


## Every box shape of a static body on the obstacle layer, such as a parked car. Road users are
## animatable bodies and come into the snapshot as themselves instead. Other shapes are not seen,
## and the boxes are collected again only when a static body or shape enters or leaves the tree,
## since static obstacles are not expected to move.
func _collect_statics() -> void:
	_statics.clear()
	for node in get_tree().root.find_children("*", "StaticBody3D", true, false):
		var body := node as StaticBody3D
		if body == null or body is AnimatableBody3D or not body.is_inside_tree() \
				or (body.collision_layer & Layers.OBSTACLE) == 0:
			continue
		for child in body.get_children():
			var shape := child as CollisionShape3D
			if shape and shape.shape is BoxShape3D and not shape.disabled:
				var size: Vector3 = shape.shape.size
				_statics.append(TrafficSnapshot.box_at(body, shape.global_transform, size.z, size.x,
					Vector3.ZERO))


func _on_tree_changed(node: Node) -> void:
	if node is CollisionShape3D or (node is StaticBody3D and not node is AnimatableBody3D):
		_statics_dirty = true
