class_name TestCase
extends RefCounted
## Base of every test case under [code]res://tests/cases/[/code]. A case overrides [method run],
## awaits frames through [member physics_frame] and [member process_frame], adds nodes under
## [member root], and asserts with the [code]expect[/code] helpers, which count passes and
## failures for the runner.

const RUNNER := preload("res://scenarios/scenes/exam_runner.tscn")
const STOP_JUNCTION := preload("res://scenarios/scenes/stop_junction/stop_junction.tscn")
const FAULTS := "res://scenarios/data/faults/%s.tres"
## The centre of the right-hand lane; scenarios are built with the car driving towards -Z in it.
const LANE_X := 1.75

var passed := 0
var failed := 0
var tree: SceneTree
var root: Window
var physics_frame: Signal
var process_frame: Signal


func setup(p_tree: SceneTree) -> void:
	tree = p_tree
	root = tree.root
	physics_frame = tree.physics_frame
	process_frame = tree.process_frame


## The case's tests; awaited by the runner.
func run() -> void:
	pass


func expect(condition: bool, what: String) -> void:
	if condition:
		passed += 1
		if OS.has_environment("TESTS_VERBOSE"):
			print("ok: ", what)
	else:
		failed += 1
		printerr("FAIL: ", what)


## The attempt completed and passed with no faults.
func expect_clean(r: ScenarioResult, what: String) -> void:
	expect(r.reason == &"completed" and r.passed and r.faults.is_empty(), _with(what, r))


## [param id] is the attempt's only fault, and it ended for [param reason]; an empty reason
## accepts any ending.
func expect_only(r: ScenarioResult, id: StringName, what: String, reason := &"completed") -> void:
	expect((reason.is_empty() or r.reason == reason) and r.faults.size() == 1 and r.has_fault(id),
		_with(what, r))


## The attempt was eliminated, with [param id] among its faults.
func expect_eliminated(r: ScenarioResult, id: StringName, what: String) -> void:
	expect(r.reason == &"eliminated" and r.has_fault(id), _with(what, r))


## A point in the right-hand lane, [param z] along it, or [param x] across.
func at(z: float, x := LANE_X) -> Vector3:
	return Vector3(x, 0.0, z)


func frames(n: int) -> void:
	for i in n:
		await physics_frame


## Drives a scenario's car along [param legs] and returns the result.
## Legs: {to: Vector3, speed: m/s} moves in a straight line, facing the target, or facing away
## from it with reverse = true, or keeping its heading with crab = true; {wait: s} stays put;
## {turn: degrees} turns in place (positive is left); {indicator: Indicator} sets the probe's
## indicator; {look: degrees} turns the driver's view to that angle (positive is left).
## [param on_spawn] is called with the runner once the car is placed, and [param on_end] just
## before it is freed. Without a scenario, the stop junction is driven.
func drive(legs: Array, scenario: PackedScene = null, on_spawn := Callable(),
		on_end := Callable()) -> ScenarioResult:
	var runner: ExamRunner = RUNNER.instantiate()
	runner.print_results = false
	runner.scenario_scene = scenario if scenario else STOP_JUNCTION
	root.add_child(runner)
	if on_spawn.is_valid():
		on_spawn.call(runner)
	var car: Node3D = runner.car
	car.input_enabled = false
	var session := runner.session
	var dt := 1.0 / Engine.physics_ticks_per_second
	await physics_frame
	for leg: Dictionary in legs:
		if leg.has("indicator"):
			VehicleProbe.of(car).indicator = leg.indicator
			continue
		if leg.has("look"):
			car.driver_view.reset_look()
			car.driver_view.turn(deg_to_rad(leg.look), 0.0)
			continue
		if leg.has("turn"):
			car.rotate_y(deg_to_rad(leg.turn))
			await physics_frame
			continue
		if leg.has("wait"):
			var waited := 0.0
			while waited < leg.wait and session.is_running():
				await physics_frame
				waited += dt
			continue
		var target: Vector3 = leg.to
		while session.is_running() and car.global_position.distance_to(target) > 0.001:
			var pos := car.global_position
			var dir := target - pos
			dir.y = 0.0
			if dir.length() > 0.01 and not leg.get("crab", false):
				car.look_at(pos - dir if leg.get("reverse", false) else pos + dir, Vector3.UP)
			car.global_position = pos.move_toward(target, leg.speed * dt)
			await physics_frame
	for i in 60:
		if not session.is_running():
			break
		await physics_frame
	if session.is_running():
		session.abort()
	var result := session.result
	if on_end.is_valid():
		on_end.call(runner)
	runner.queue_free()
	await process_frame
	return result


## A runner on the stop junction that is not driven by the tests; for the probe and session.
func spawn_runner(scenario: PackedScene = null) -> ExamRunner:
	var runner: ExamRunner = RUNNER.instantiate()
	runner.print_results = false
	runner.scenario_scene = scenario if scenario else STOP_JUNCTION
	root.add_child(runner)
	return runner


## One physics tick at the tests' rate.
const DT := 1.0 / 60.0


## A simulation with no scene and no exam, stepped by hand with [method tick]: lanes, road users,
## lights, and, when [param car] is given, the player's car standing there (its pose is the
## test's to move). Free it with [method end_sim].
func sim(car := Transform3D(Basis(), Vector3.INF)) -> WorldRunner:
	var runner := WorldRunner.new()
	Simulation.empty_world(runner.world)
	Simulation.add_systems(runner, false)
	if car.origin != Vector3.INF:
		runner.world.spawn({vehicle = {transform = car, name = &"Car"}})
	return runner


func tick(runner: WorldRunner, count := 1) -> void:
	for i in count:
		runner.step(DT)


func end_sim(runner: WorldRunner) -> void:
	runner.stop()
	runner.free()


## Moves the car of a hand-stepped simulation, as the shell would read it from a car node.
func place_car(runner: WorldRunner, at: Vector3, facing := Vector3.FORWARD) -> void:
	var world := runner.world
	var t := Transform3D(Basis.looking_at(facing, Vector3.UP), at)
	world.store(Schema.VEHICLE).set_value(Schema.single(world, Schema.VEHICLE), &"transform", t)


func car_entity(runner: WorldRunner) -> int:
	return Schema.single(runner.world, Schema.VEHICLE)


## A straight path from [param from] to [param to]; a lane with rules when [param settings] sets
## [code]is_lane[/code].
func path(runner: WorldRunner, from: Vector3, to: Vector3, settings := {}) -> LaneData:
	return Simulation.add_path(runner.world, PackedVector3Array([from, to]), settings)


func road_user(runner: WorldRunner, lane: LaneData, settings := {}) -> int:
	return Simulation.add_agent(runner.world, lane, settings)


func state_of(runner: WorldRunner, agent: int) -> AgentState:
	return runner.world.get_value(Schema.AGENT, agent, &"state")


## Appends every event of a hand-stepped simulation to [param into].
func record_sim(runner: WorldRunner, into: Array) -> void:
	runner.events_emitted.connect(func(events: Array[WorldEvent]) -> void:
		into.append_array(events))


## Appends every world event of [param runner]'s attempt from now on to [param into].
func record_events(runner: ExamRunner, into: Array) -> void:
	runner.world_runner.events_emitted.connect(func(events: Array[WorldEvent]) -> void:
		into.append_array(events))


## Appends a line "<road user> <reaction>" to [param into] for every reaction in [param runner]'s
## attempt from now on, named as they happen.
func record_reactions(runner: ExamRunner, into: Array) -> void:
	var world := runner.world()
	runner.world_runner.events_emitted.connect(func(events: Array[WorldEvent]) -> void:
		for event in events:
			if event.kind == &"reacted":
				into.append("%s %s" % [world.get_value(Schema.AGENT, event.entity, &"name"),
					event.data.kind]))


## The state of the road user named [param agent_name] in [param runner]'s world.
func agent_state(runner: ExamRunner, agent_name: StringName) -> AgentState:
	var world := runner.world()
	var id := Schema.find(world, Schema.AGENT, agent_name)
	return world.get_value(Schema.AGENT, id, &"state") if id else null


## The car as [param runner]'s world sees it now.
func car_state(runner: ExamRunner) -> CarState:
	return CarState.read(runner.world())


func _with(what: String, r: ScenarioResult) -> String:
	return "%s: %s" % [what, r.summary() if r else "no result"]
