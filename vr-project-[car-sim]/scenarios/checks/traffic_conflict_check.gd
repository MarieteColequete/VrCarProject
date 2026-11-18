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


func rule_script() -> Script:
	return TrafficConflictRule


func rule_params(bake: Bake) -> Dictionary:
	return {agents = bake.ids_of(agents), fault = hard_braking_fault}
