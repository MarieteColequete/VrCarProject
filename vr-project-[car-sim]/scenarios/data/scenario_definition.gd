class_name ScenarioDefinition
extends Resource
## What a scenario is, apart from its world: the text shown before it, its time limit, how it is
## scored, and which car drives it.

@export var title: String
@export_multiline var briefing: String
## Seconds the attempt may take before it ends as a timeout; 0 for no limit.
@export var time_limit := 0.0
@export var policy: ScoringPolicy
## The car scene spawned at the scenario's spawn point. It needs a [VehicleProbe] child.
@export var car_scene: PackedScene
