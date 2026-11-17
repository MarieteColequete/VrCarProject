class_name MarkingHit
extends RefCounted
## A road marking crossed by a moving point: which marking, where, and the side crossed onto.

var marking: RoadMarking
## Where the point crossed the marking, world space.
var point: Vector3
## Horizontal unit normal of the marking, pointing to the side the point crossed onto.
var normal: Vector3


func _init(p_marking: RoadMarking, p_point: Vector3, p_normal: Vector3) -> void:
	marking = p_marking
	point = p_point
	normal = p_normal
