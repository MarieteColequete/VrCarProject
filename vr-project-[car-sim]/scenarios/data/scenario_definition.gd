class_name ScenarioDefinition
extends Resource
## What a scenario is, apart from its world: how menus list it, the text shown before it, its
## time limit, how it is scored, and which car drives it. Each scenario keeps its definition in
## [code]definition.tres[/code] beside its scene, and the [ScenarioCatalogue] lists them. Free
## drive's definition, [code]res://scenarios/data/free_drive.tres[/code], has no scene of its own:
## it judges whichever map is driven.

## A stable name for saves and links, such as [code]stop_junction[/code].
@export var id: StringName
@export var title: String
## The group menus list it under, such as "Junctions" or "Parking".
@export var category: String
## 1 for the simplest scenarios, higher for harder ones.
@export_range(1, 5) var difficulty := 1
@export_multiline var briefing: String
## Seconds the attempt may take before it ends as a timeout; 0 for no limit.
@export var time_limit := 0.0
## The scenario scene; a path rather than a reference, since the scene refers back to this
## definition.
@export_file("*.tscn") var scene_path: String
@export var policy: ScoringPolicy = preload("res://scenarios/data/default_policy.tres")
## The car scene spawned at the scenario's spawn point. It needs a [VehicleProbe] child.
@export var car_scene: PackedScene = preload("res://scenarios/scenes/debug_car.tscn")


## The scenario scene, loaded.
func load_scene() -> PackedScene:
	return load(scene_path) as PackedScene if not scene_path.is_empty() else null
