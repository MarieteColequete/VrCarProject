class_name TestCase
extends RefCounted
## Base of every test case under [code]res://tests/cases/[/code]. A case overrides [method run],
## awaits frames through [member physics_frame] and [member process_frame], adds nodes under
## [member root], and asserts with the [code]expect[/code] helpers, which count passes and
## failures for the runner.

const RUNNER := preload("res://scenarios/scenes/exam_runner.tscn")
const PLAYER_CAR := preload("res://scenarios/scenes/player_car.tscn")
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


## A flat road under [member root] for a car driven without a map, its top at y = 0, of the
## asphalt's [BodyType], or [param type]'s. The caller frees it.
func ground(size := 400.0, type := &"asphalt") -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "TestGround"
	BodyType.of(type).apply(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(size, 0.2, size)
	shape.shape = box
	shape.position.y = -0.1
	body.add_child(shape)
	root.add_child(body)
	return body


func frames(n: int) -> void:
	for i in n:
		await physics_frame


## The player's car, with [param settings] (property to value) set before it enters the tree,
## added under [member root]. The caller frees it.
func spawn_car(settings := {}) -> Node3D:
	var car: Node3D = PLAYER_CAR.instantiate()
	for key: StringName in settings:
		car.set(key, settings[key])
	root.add_child(car)
	return car


## Whether input action [param action] has a binding of the class [param type].
static func has_event(action: StringName, type: String) -> bool:
	for event in InputMap.action_get_events(action):
		if event.is_class(type):
			return true
	return false


## The Asset Library's entry for the model [param model_name]; null when there is none.
static func catalogue_entry(model_name: String) -> AssetCatalogue.Entry:
	for entry in AssetCatalogue.scan():
		if entry.model_name == model_name:
			return entry
	return null


## A straight curve [param length] metres long along -Z, centred on the origin.
static func straight(length: float) -> Curve3D:
	var curve := Curve3D.new()
	curve.add_point(Vector3(0, 0, length / 2.0))
	curve.add_point(Vector3(0, 0, -length / 2.0))
	return curve


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
		if leg.has("look_at"):
			look_at_mirror(car, leg.look_at)
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
func place_car(runner: WorldRunner, where: Vector3, facing := Vector3.FORWARD) -> void:
	var world := runner.world
	var t := Transform3D(Basis.looking_at(facing, Vector3.UP), where)
	world.store(Schema.VEHICLE).set_value(Schema.single(world, Schema.VEHICLE), &"transform", t)


func car_entity(runner: WorldRunner) -> int:
	return Schema.single(runner.world, Schema.VEHICLE)


## A straight path from [param from] to [param to]; a lane with rules when [param settings] sets
## [code]is_lane[/code].
func path(runner: WorldRunner, from: Vector3, to: Vector3, settings := {}) -> LaneData:
	return Simulation.add_path(runner.world, PackedVector3Array([from, to]), settings)


func road_user(runner: WorldRunner, lane: LaneData, settings := {}) -> int:
	return Simulation.add_agent(runner.world, lane, settings)


## Road user [param agent] of a hand-stepped simulation, as plain values: every column, with its
## reaction by name.
func state_of(runner: WorldRunner, agent: int) -> Dictionary:
	return row_of(runner.world, agent)


## Road user [param id] of [param world] as plain values: every column, with its reaction by name.
func row_of(world: World, id: int) -> Dictionary:
	var store := world.store(Schema.AGENT)
	var out := {}
	for column: StringName in store.columns:
		out[column] = store.get_value(id, column)
	out.reaction = AgentTable.KIND_NAMES[out.reaction]
	return out


## Seconds until road user [param agent] reaches [param offset] along its path.
func time_to(runner: WorldRunner, agent: int, offset: float) -> float:
	var table := AgentTable.view_of(runner.world.store(Schema.AGENT))
	return table.time_to(table.row_of(agent), offset, runner.world.resources[Schema.LANES])


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


## The road user named [param agent_name] in [param runner]'s world, as plain values; empty when
## there is none.
func agent_state(runner: ExamRunner, agent_name: StringName) -> Dictionary:
	var world := runner.world()
	var id := Schema.find(world, Schema.AGENT, agent_name)
	return row_of(world, id) if id else {}


## The car as [param runner]'s world sees it now.
func car_state(runner: ExamRunner) -> CarState:
	return CarState.read(runner.world())


func _with(what: String, r: ScenarioResult) -> String:
	return "%s: %s" % [what, r.summary() if r else "no result"]


## Turns the car's flat view from its eye to its mirror [param index] (0 interior, 1 left,
## 2 right), as a driver checking it would.
func look_at_mirror(car: Node3D, index: int) -> void:
	var probe := VehicleProbe.of(car)
	var view: DriverView = car.driver_view
	view.reset_look()
	var to := probe.global_transform * probe.mirrors[index] - probe.eye_position()
	var local := car.global_basis.inverse() * to
	var flat := Vector2(local.x, local.z).length()
	view.turn(atan2(-local.x, -local.z), atan2(local.y, flat))
