class_name NoParkingZone
extends TriggerZone
## An area where parking is not allowed, such as the approach to a junction or a crossing, or a
## bus stop. Its shape is a [CollisionShape3D] child; [member reason] names the rule for the
## result and the UI.

@export var reason := "No parking"


func _ready() -> void:
	super()
	add_to_group(&"no_parking_zone")
