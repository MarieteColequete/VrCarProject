@tool
class_name ContactCheck
extends Check
## Contact between the car and anything on a judged layer ([constant Layers.JUDGED]): obstacles,
## traffic, and pedestrians. A body in the
## pedestrian group, or on the pedestrian layer, gives the pedestrian fault. Each body is
## reported once per attempt.

@export var obstacle_fault: FaultDef = preload("res://scenarios/data/faults/contact_obstacle.tres")
@export var pedestrian_fault: FaultDef = preload("res://scenarios/data/faults/contact_pedestrian.tres")


func rule_script() -> Script:
	return ContactRule


func rule_params(_bake: Bake) -> Dictionary:
	return {obstacle_fault = obstacle_fault, pedestrian_fault = pedestrian_fault}
