class_name WorldEvent
extends RefCounted
## Something that happened in one tick of the [World]: a fault committed, a road user reacting, a
## light changing, the car entering a zone. Events are values: systems create them in a [Delta],
## the [World] collects them in order, and the shell hands them to whoever listens (the session,
## the HUD, the tests). Nothing reacts to an event inside the tick that produced it.

## What happened, such as [code]&"fault"[/code] or [code]&"reacted"[/code].
var kind: StringName
## The entity it happened to; 0 when it concerns no entity.
var entity := 0
## Simulation seconds when it happened.
var time := 0.0
## The details, by name.
var data := {}


func _init(p_kind: StringName, p_entity := 0, p_data := {}) -> void:
	kind = p_kind
	entity = p_entity
	data = p_data


func get_data(key: StringName, fallback: Variant = null) -> Variant:
	return data.get(key, fallback)


func _to_string() -> String:
	return "%s(%d) %s" % [kind, entity, data]
