@tool
class_name ContactCheck
extends Check
## Contact between the car and anything on the obstacle or pedestrian layers. A body in the
## pedestrian group, or on the pedestrian layer, gives the pedestrian fault. Each body is
## reported once per attempt.

@export var obstacle_fault: FaultDef = preload("res://scenarios/data/faults/contact_obstacle.tres")
@export var pedestrian_fault: FaultDef = preload("res://scenarios/data/faults/contact_pedestrian.tres")

var _touched: Array[Node3D] = []


func _on_bound() -> void:
	probe().contact_started.connect(_on_contact)


func _on_contact(body: Node3D) -> void:
	if not is_live() or _touched.has(body):
		return
	_touched.append(body)
	var pedestrian := body.is_in_group(Layers.GROUP_PEDESTRIAN)
	if body is CollisionObject3D:
		pedestrian = pedestrian or (body.collision_layer & Layers.PEDESTRIAN) != 0
	report_here(pedestrian_fault if pedestrian else obstacle_fault, body)
