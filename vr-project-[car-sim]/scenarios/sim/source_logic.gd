class_name SourceLogic
extends RefCounted
## Steady flows of road users onto lanes: up to a source's count of cars, the first after its
## start delay and the rest at headways drawn between its minimum and maximum, each only once the
## lane's entry is clear. Headways and routes come from the source's seed, so the same seed always
## gives the same traffic.


## The source system: spawns the road users due this tick.
static func run(world: World, dt: float) -> Delta:
	var d := Delta.new()
	var s := world.store(Schema.SOURCE)
	if s == null:
		return d
	var lanes: Dictionary = world.resources.get(Schema.LANES, {})
	var agents := AgentTable.view_of(world.store(Schema.AGENT))
	for row in s.size():
		var id := s.ids[row]
		var src := {}
		for column: StringName in s.columns:
			src[column] = s.columns[column][row]
		var clock: float = src.clock + dt
		d.write(Schema.SOURCE, id, &"clock", clock)
		var lane: LaneData = lanes.get(src.lane)
		if lane == null or src.spawned >= src.count or clock < src.next_at \
				or not entry_is_clear(src, agents):
			continue
		var rng := RandomNumberGenerator.new()
		rng.state = src.rng_state
		var config := {name = StringName("%s%d" % [src.name, src.spawned + 1]), speed = src.speed,
			route = PackedInt64Array(src.route), route_seed = rng.randi()}
		var colours: Array = src.colours
		if not colours.is_empty():
			config.colour = colours[src.spawned % colours.size()]
		d.spawn({agent = AgentTable.spawn_values(config, lane, lanes)})
		d.write_all(Schema.SOURCE, id, {spawned = src.spawned + 1,
			next_at = clock + rng.randf_range(src.min_headway, src.max_headway),
			rng_state = rng.state})
	return d


## Whether no road user is within the entry gap of the source's lane start: its entry gap, or the
## room to stop comfortably (3 m/s²) from its speed plus 2 m, whichever is longer.
static func entry_is_clear(src: Dictionary, agents: AgentTable) -> bool:
	var needed := maxf(src.entry_gap, src.speed * src.speed / 6.0 + 2.0)
	for i in agents.size():
		if agents.lane[i] == src.lane and agents.progress[i] < needed + agents.body_size[i].z:
			return false
	return true
