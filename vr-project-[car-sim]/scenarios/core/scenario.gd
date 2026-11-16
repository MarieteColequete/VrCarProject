class_name Scenario
extends Node3D
## The root of a scenario scene: the world, a spawn point, and the [Check] nodes that judge it.

@export var definition: ScenarioDefinition
## Where and facing which way the car starts.
@export var spawn_point: Marker3D


## Every [Check] in the scene, in tree order.
func get_checks() -> Array[Check]:
	var found: Array[Check] = []
	_collect(self, found)
	return found


func _collect(node: Node, found: Array[Check]) -> void:
	for child in node.get_children():
		if child is Check:
			found.append(child)
		_collect(child, found)
