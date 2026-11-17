@tool
class_name TrafficConflictCheck
extends Check
## Making other road users react: when a road user is forced to brake hard because the session's
## car got in its way, such as by cutting in or pulling out in front of it, that is a fault. It
## watches every [ScriptedAgent] of the scenario, including those spawned during the attempt, or
## only [member agents] when that is set. Each time a road user is forced to brake is one fault.

## The road users watched; empty for all of the scenario's.
@export var agents: Array[ScriptedAgent] = []
@export var hard_braking_fault: FaultDef = preload("res://scenarios/data/faults/caused_hard_braking.tres")


func _on_bound() -> void:
	if not agents.is_empty():
		for agent in agents:
			_watch_agent(agent)
		return
	for node in session.scenario.find_children("*", "", true, false):
		if node is ScriptedAgent:
			_watch_agent(node)
	get_tree().node_added.connect(_on_node_added)


func _exit_tree() -> void:
	if get_tree() and get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func _on_node_added(node: Node) -> void:
	if node is ScriptedAgent and session and session.scenario \
			and session.scenario.is_ancestor_of(node):
		_watch_agent(node)


func _watch_agent(agent: ScriptedAgent) -> void:
	if agent and not agent.forced_to_brake.is_connected(_on_forced.bind(agent)):
		agent.forced_to_brake.connect(_on_forced.bind(agent))


func _on_forced(cause: Node3D, _deceleration: float, agent: ScriptedAgent) -> void:
	if is_live() and VehicleProbe.of(cause) == probe():
		report_here(hard_braking_fault, agent)
