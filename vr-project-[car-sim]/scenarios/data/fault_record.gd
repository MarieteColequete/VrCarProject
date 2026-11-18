class_name FaultRecord
extends RefCounted
## One fault committed during a session: what, when, and where.

var def: FaultDef
## Seconds since the session started running.
var time: float
var position: Vector3


func _init(p_def: FaultDef, p_time: float, p_position: Vector3) -> void:
	def = p_def
	time = p_time
	position = p_position


func _to_string() -> String:
	return "%s [%s] at %.1f s" % [def.title, def.tier, time]
