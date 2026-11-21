class_name Scenario
extends Node3D
## The root of a scenario scene: a map, a spawn point, the [Check] nodes that judge it, and
## optionally the [ScenarioStep]s of its task. The world comes from a [RoadMap] instanced as the
## [code]Map[/code] child; the scenario adds what is judged on it. The scene is the authoring side;
## when it loads, a [Bake] reads it, map included, into the simulation's [World].

const FREE_DRIVE := preload("res://scenarios/data/free_drive.tres")

@export var definition: ScenarioDefinition
## The map the scenario is set on, usually its [code]Map[/code] child.
@export var map: RoadMap
## Where and facing which way the car starts; the map's first [MapSpawn] when empty.
@export var spawn_point: Marker3D


## A scenario for driving [param map_scene] freely: the free drive definition, the map, and the
## checks that need nothing but the map (contact, road markings, parking places, and conflicts with
## other road users). The car starts at the map's spawn number [param spawn].
static func free_drive(map_scene: PackedScene, spawn := 0) -> Scenario:
	var scenario := Scenario.new()
	scenario.name = "FreeDrive"
	scenario.definition = FREE_DRIVE
	var road_map := map_scene.instantiate() as RoadMap
	assert(road_map != null, "The map scene's root needs the RoadMap script")
	road_map.name = "Map"
	scenario.add_child(road_map)
	scenario.map = road_map
	var spawns := road_map.spawns()
	if not spawns.is_empty():
		scenario.spawn_point = spawns[clampi(spawn, 0, spawns.size() - 1)]
	var checks := Node3D.new()
	checks.name = "Checks"
	scenario.add_child(checks)
	for check: Check in [ContactCheck.new(), LineCheck.new(), ParkingChoiceCheck.new(),
			TrafficConflictCheck.new()]:
		check.name = check.get_script().get_global_name()
		checks.add_child(check)
	return scenario


## Where the car starts: [member spawn_point], or else the map's first spawn.
func start() -> Marker3D:
	if spawn_point:
		return spawn_point
	var spawns := map.spawns() if map else ([] as Array[MapSpawn])
	return spawns[0] if not spawns.is_empty() else null


## Every [Check] in the scene, in tree order.
func get_checks() -> Array[Check]:
	var found: Array[Check] = []
	for node in nodes():
		if node is Check:
			found.append(node)
	return found


## Every [ScenarioStep] in the scene, in tree order, which is the order they run in.
func get_steps() -> Array[ScenarioStep]:
	var found: Array[ScenarioStep] = []
	for node in nodes():
		if node is ScenarioStep:
			found.append(node)
	return found


## The scene's nodes below the root, in tree order. Internal children, such as the edges a
## [ParkingBay] draws for itself, belong to their owner and are left out.
func nodes() -> Array[Node]:
	var out: Array[Node] = []
	collect(self, out)
	return out


## Appends the nodes below [param node] to [param out], in tree order, internal children left out.
static func collect(node: Node, out: Array[Node]) -> void:
	for child in node.get_children():
		out.append(child)
		collect(child, out)
