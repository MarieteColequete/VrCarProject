@tool
class_name GoalCheck
extends Check
## The end of a step, or of the scenario: entering the zone completes [member step] when it is
## set and current, and otherwise completes the attempt.

@export var zone: TriggerZone
## The step this goal ends; empty to end the attempt.
@export var step: ScenarioStep


func required_exports() -> PackedStringArray:
	return ["zone"]


func rule_script() -> Script:
	return GoalRule


func rule_params(bake: Bake) -> Dictionary:
	return {zone = bake.id_of(zone), step = bake.step_index(step)}
