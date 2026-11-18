class_name Simulation
extends RefCounted
## The simulation's schedule, in one place: which systems run, in which stage, on a
## [WorldRunner]. The [ExamRunner] uses it with the exam; tests use it without, on a world they
## build by hand.
##
## Stages: 1 the car's motion; 2 zones and contacts; 3 lights and traffic sources; 4 the rules and
## the session. Road users think across ticks on worker threads, through the returned pipeline.


## Adds the systems to [param runner], the exam's when [param exam] is set, and returns the traffic
## pipeline.
static func add_systems(runner: WorldRunner, exam := true) -> TrafficPipeline:
	runner.add_system(VehicleLogic.run, 1)
	runner.add_system(Detection.zones, 2)
	runner.add_system(Detection.contacts, 2)
	runner.add_system(LightLogic.run, 3)
	runner.add_system(SourceLogic.run, 3)
	if exam:
		runner.add_system(ExamLogic.run, 4)
	var traffic := TrafficPipeline.new()
	runner.add_pipelined(traffic)
	return traffic


## A world with the schema declared and no scenario: for building a simulation by hand.
static func empty_world(world: World) -> void:
	Schema.define(world)
	world.resources[&"lanes"] = {}
	world.resources[Schema.MARKINGS] = MarkingIndex.new()


## Adds a plain path from [param points] (world space) to [param world] as a lane entity, and
## returns it; [param settings] sets [LaneData] fields, such as [code]is_lane[/code] or
## [code]speed_limit[/code].
static func add_path(world: World, points: PackedVector3Array, settings := {}) -> LaneData:
	var lane := LaneData.new()
	lane.id = world.create()
	lane.curve = Curve3D.new()
	for p in points:
		lane.curve.add_point(p)
	lane.length = lane.curve.get_baked_length()
	for key: StringName in settings:
		lane.set(key, settings[key])
	world.resources[&"lanes"][lane.id] = lane
	world.store(Schema.LANE).add(lane.id, {data = lane, name = lane.name})
	return lane


## Adds a road user on [param lane] with [param settings] for its [AgentConfig] fields, and
## returns its entity.
static func add_agent(world: World, lane: LaneData, settings := {}) -> int:
	var config := AgentConfig.new()
	for key: StringName in settings:
		config.set(key, settings[key])
	var id := world.create()
	world.store(Schema.AGENT).add(id, {state = AgentLogic.spawn(config, lane,
		world.resources[&"lanes"]), name = config.name})
	return id
