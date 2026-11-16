class_name TriggerZone
extends Area3D
## A region of the road that checks watch. It only sees bodies on the vehicle layer that carry a
## [VehicleProbe], and reports the probe rather than the body. Its shape is a
## [CollisionShape3D] child, drawn in the editor.

signal vehicle_entered(probe: VehicleProbe)
signal vehicle_exited(probe: VehicleProbe)

var _inside: Array[VehicleProbe] = []


func _ready() -> void:
	collision_layer = VehicleProbe.DETECTION_LAYER
	collision_mask = VehicleProbe.VEHICLE_LAYER
	monitoring = true
	monitorable = false
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)


func contains(probe: VehicleProbe) -> bool:
	return probe != null and _inside.has(probe)


## Whether [param point] lies inside the zone's first box shape, grown by [param margin] metres
## on the ground plane; for things the zone does not detect itself, such as pedestrians.
func contains_point(point: Vector3, margin := 0.0) -> bool:
	for child in get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D:
			var local: Vector3 = child.global_transform.affine_inverse() * point
			var half: Vector3 = child.shape.size * 0.5
			return absf(local.x) <= half.x + margin and absf(local.z) <= half.z + margin \
				and absf(local.y) <= half.y
	return false


func _on_body_entered(body: Node3D) -> void:
	var probe := VehicleProbe.of(body)
	if probe and not _inside.has(probe):
		_inside.append(probe)
		vehicle_entered.emit(probe)


func _on_body_exited(body: Node3D) -> void:
	var probe := VehicleProbe.of(body)
	if probe and _inside.has(probe):
		_inside.erase(probe)
		vehicle_exited.emit(probe)
