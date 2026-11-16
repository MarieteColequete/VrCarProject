class_name GoalCheck
extends Check
## The end of a step, or of the scenario: entering the zone completes [member step] when it is
## set and current, and otherwise completes the attempt.

@export var zone: TriggerZone
## The step this goal ends; empty to end the attempt.
@export var step: ScenarioStep


func _on_bound() -> void:
	zone.vehicle_entered.connect(func(p: VehicleProbe) -> void:
		if p != probe() or not is_live():
			return
		if step:
			session.complete_step(step)
		else:
			session.complete())
