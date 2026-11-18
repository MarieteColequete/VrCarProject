class_name Scenario
extends Node3D
## The root of a scenario scene: the world, a spawn point, the [Check] nodes that judge it, and
## optionally the [ScenarioStep]s of its task. The scene is the authoring side; when it loads, a
## [Bake] reads it into the simulation's [World].

@export var definition: ScenarioDefinition
## Where and facing which way the car starts.
@export var spawn_point: Marker3D


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
	_collect(self, out)
	return out


static func _collect(node: Node, out: Array[Node]) -> void:
	for child in node.get_children():
		out.append(child)
		_collect(child, out)
