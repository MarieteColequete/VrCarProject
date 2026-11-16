class_name GoalCheck
extends Check
## The end of the scenario: the attempt completes when the car enters the zone.

@export var zone: TriggerZone


func _on_bound() -> void:
	zone.vehicle_entered.connect(func(p: VehicleProbe) -> void:
		if p == probe() and is_live():
			session.complete())
