@tool
class_name ExamRunner
extends Node3D
## Loads a scenario scene, spawns its car at the spawn point, and runs an [ExamSession] on it.
## The UI reaches the session through [member session], and picks scenarios from the
## [ScenarioCatalogue] with [method load_definition].

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
var car: Node3D

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


## Loads the scenario a catalogue entry describes.
func load_definition(definition: ScenarioDefinition) -> void:
	var scene := definition.load_scene() if definition else null
	if scene == null:
		push_error("The definition '%s' names no loadable scene" % [definition.id if definition else &""])
		return
	load_scenario(scene)


func load_scenario(scene: PackedScene) -> void:
	scenario_scene = scene
	_clear()
	scenario = scene.instantiate() as Scenario
	assert(scenario != null, "The scenario scene's root needs the Scenario script")
	add_child(scenario)
	var car_scene := car_scene_override if car_scene_override else scenario.definition.car_scene
	car = car_scene.instantiate() as Node3D
	# Placed before it enters the tree, so no zone sees it at the origin for a tick.
	car.transform = global_transform.affine_inverse() * scenario.spawn_point.global_transform
	add_child(car)
	var probe := VehicleProbe.of(car)
	assert(probe != null, "The car scene needs a VehicleProbe child")
	probe.reset()
	scenario_loaded.emit(scenario, car)
	# The session starts on the next idle step, so a listener connected right after the runner
	# entered the tree still gets briefing_started, started, and the first step_changed.
	_start_session.call_deferred(scenario, probe)


func _start_session(p_scenario: Scenario, probe: VehicleProbe) -> void:
	if p_scenario != scenario or not is_instance_valid(probe):
		return
	session.setup(p_scenario, probe)
	if autostart:
		session.begin()


func _reload() -> void:
	load_scenario.call_deferred(scenario_scene)


func _clear() -> void:
	for node: Node in [scenario, car]:
		if is_instance_valid(node):
			remove_child(node)
			node.queue_free()
	scenario = null
	car = null



func _get_configuration_warnings() -> PackedStringArray:
	if scenario_scene == null:
		return ["No scenario scene: the runner waits for load_scenario or load_definition."]
	return []
