class_name Scenario
extends Node3D
## The root of a scenario scene: the world, a spawn point, the [Check] nodes that judge it, and
## optionally the [ScenarioStep]s of its task.

@export var definition: ScenarioDefinition
## Where and facing which way the car starts.
@export var spawn_point: Marker3D


## Every [Check] in the scene, in tree order.
func get_checks() -> Array[Check]:
	var found: Array[Check] = []
	for node in _descendants(self):
		if node is Check:
			found.append(node)
	return found


## Every [ScenarioStep] in the scene, in tree order, which is the order they run in.
func get_steps() -> Array[ScenarioStep]:
	var found: Array[ScenarioStep] = []
	for node in _descendants(self):
		if node is ScenarioStep:
			found.append(node)
	return found


func _descendants(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	for child in node.get_children():
		out.append(child)
		out.append_array(_descendants(child))
	return out
