@tool
class_name ExamRunner
extends Node3D
## Loads a scenario scene, or a map for free drive, spawns its car at the spawn point, bakes both
## into a [World], and runs
## the simulation on a [WorldRunner]: the systems below judge the attempt, move traffic, and run
## the lights, and the views draw it. The UI reaches the attempt through [member session], and
## picks scenarios from the [ScenarioCatalogue] with [method load_definition].
##
## The schedule of a tick is the [Simulation]'s.

## Emitted each time a scenario and car are spawned, including after a restart.
signal scenario_loaded(scenario: Scenario, car: Node3D)

## The scenario loaded when the runner enters the tree; empty to wait for
## [method load_scenario] or [method load_definition].
@export var scenario_scene: PackedScene
## Replaces the scenario's own car scene when set.
@export var car_scene_override: PackedScene
## Starts the attempt right after the briefing, without waiting for the UI.
@export var autostart := true
## Prints each result to the output.
@export var print_results := true

var scenario: Scenario
## The map being driven freely, after [method load_map]; null while a scenario is loaded.
var map_scene: PackedScene
var map_spawn := 0
var car: Node3D
## The simulation of the current scenario.
var world_runner: WorldRunner
## The road users' pipeline, for its timings.
var traffic: TrafficPipeline

var _traffic_view: TrafficView
var _bake: Bake

@onready var session: ExamSession = $Session


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	session.restart_requested.connect(_reload)
	session.finished.connect(func(result: ScenarioResult) -> void:
		if print_results:
			print("[%s] %s" % [scenario.definition.title, result.summary()]))
	if scenario_scene:
		load_scenario(scenario_scene)


## The current scenario's world; null before one is loaded.
func world() -> World:
	return world_runner.world if world_runner else null


## Loads the scenario a catalogue entry describes.
func load_definition(definition: ScenarioDefinition) -> void:
	var scene := definition.load_scene() if definition else null
	if scene == null:
		push_error("The definition '%s' names no loadable scene" % [definition.id if definition else &""])
		return
	load_scenario(scene)


func load_scenario(scene: PackedScene) -> void:
	scenario_scene = scene
	map_scene = null
	_clear()
	var loaded := scene.instantiate() as Scenario
	assert(loaded != null, "The scenario scene's root needs the Scenario script")
	_start(loaded)


## Loads [param scene], a map, for free drive, with the car at its spawn number [param spawn]. See
## [method Scenario.free_drive].
func load_map(scene: PackedScene, spawn := 0) -> void:
	scenario_scene = null
	map_scene = scene
	map_spawn = spawn
	_clear()
	_start(Scenario.free_drive(scene, spawn))


func _start(loaded: Scenario) -> void:
	scenario = loaded
	add_child(scenario)
	var start := scenario.start()
	assert(start != null, "The scenario needs a spawn point or a map with a MapSpawn")
	var car_scene := car_scene_override if car_scene_override else scenario.definition.car_scene
	car = car_scene.instantiate() as Node3D
	# An exam attempt drives with the exam's aids; free drive with the player's setting.
	if &"assist_preset" in car and scenario.definition != Scenario.FREE_DRIVE:
		car.set(&"assist_preset", "exam")
	car.transform = global_transform.affine_inverse() * start.global_transform
	add_child(car)
	car.reset_physics_interpolation()
	var probe := VehicleProbe.of(car)
	assert(probe != null, "The car scene needs a VehicleProbe child")
	world_runner = WorldRunner.new()
	world_runner.name = "World"
	add_child(world_runner)
	_bake = Bake.scene(world_runner.world, scenario, probe)
	for node in _bake.to_free:
		node.queue_free()
	_wire(probe, _bake)
	session.attach(world_runner)
	scenario_loaded.emit(scenario, car)
	# The session starts on the next idle step, so a listener connected right after the runner
	# entered the tree still gets briefing_started, started, and the first step_changed.
	_start_session.call_deferred(world_runner)


func _wire(probe: VehicleProbe, bake: Bake) -> void:
	var w := world_runner.world
	var vehicle := Schema.single(w, Schema.VEHICLE)
	world_runner.add_input(func(_world: World, _dt: float) -> Delta:
		var d := Delta.new()
		if is_instance_valid(probe):
			d.write_all(Schema.VEHICLE, vehicle, probe.reading())
		return d)
	traffic = Simulation.add_systems(world_runner)
	var capacity := w.store(Schema.AGENT).size()
	for row in w.store(Schema.SOURCE).size():
		capacity += w.store(Schema.SOURCE).column(&"count")[row]
	_traffic_view = TrafficView.new(scenario, capacity)
	if car is CollisionObject3D:
		_traffic_view.ignore = (car as CollisionObject3D).get_rid()
	world_runner.add_view(_traffic_view.draw)
	# The knocks road users give the car ([Impacts]).
	world_runner.add_view(func(world: World) -> void:
		if is_instance_valid(car) and car.has_method(&"knock"):
			car.call(&"knock", world.store(Schema.VEHICLE).get_value(vehicle, &"impulse")))
	var authored := bake.nodes
	world_runner.add_view(func(world: World) -> void: SceneViews.draw_lights(world, authored))
	SceneViews.place_parked_cars(w, authored)
	SceneViews.draw_lights(w, authored)
	_traffic_view.draw(w)


## Adds a road user authored after the scenario loaded, such as by a test or a director: bakes it
## into the world, frees the node, and returns its entity.
func add_road_user(agent: ScriptedAgent) -> int:
	var id := _bake.add_agent(agent)
	if agent.is_inside_tree():
		agent.queue_free()
	else:
		agent.free()
	return id


## Adds the box shapes of a static body placed after the scenario loaded, such as a van parked
## during the attempt, as obstacles road users see and the car touches.
func add_obstacle(body: StaticBody3D) -> void:
	_bake.add_obstacles([body])


func _start_session(runner: WorldRunner) -> void:
	if runner != world_runner:
		return
	session.setup()
	if autostart:
		session.begin()


func _reload() -> void:
	if map_scene:
		load_map.call_deferred(map_scene, map_spawn)
	else:
		load_scenario.call_deferred(scenario_scene)


func _clear() -> void:
	if _traffic_view:
		_traffic_view.clear()
		_traffic_view = null
	for node: Node in [scenario, car, world_runner]:
		if is_instance_valid(node):
			remove_child(node)
			node.queue_free()
	scenario = null
	car = null
	world_runner = null
	traffic = null


func _exit_tree() -> void:
	if not Engine.is_editor_hint() and _traffic_view:
		_traffic_view.clear()
		_traffic_view = null


func _get_configuration_warnings() -> PackedStringArray:
	if scenario_scene == null:
		return ["No scenario scene: the runner waits for load_scenario or load_definition."]
	return []
