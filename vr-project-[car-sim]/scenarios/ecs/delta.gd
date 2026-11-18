class_name Delta
extends RefCounted
## What a system wants changed: component values to write, entities to create or remove, and
## events that happened. A system builds a delta from what it read and returns it; it never
## writes the [World] itself. The [WorldRunner] applies deltas in a fixed order after the systems
## of a tick have run, so every system of a tick sees the same, last committed world.

var _components: Array[StringName] = []
var _ids := PackedInt64Array()
var _columns: Array[StringName] = []
var _values: Array = []
## Each spawn: a Dictionary of component name to its values.
var spawns: Array[Dictionary] = []
var despawns := PackedInt64Array()
## Each removal of one component from an entity: [component, id].
var removals: Array = []
var events: Array[WorldEvent] = []


## Writes [param value] to [param column] of [param id]'s [param component].
func write(component: StringName, id: int, column: StringName, value: Variant) -> Delta:
	_components.append(component)
	_ids.append(id)
	_columns.append(column)
	_values.append(value)
	return self


## Writes several columns of one entity's component at once.
func write_all(component: StringName, id: int, values: Dictionary) -> Delta:
	for column: StringName in values:
		write(component, id, column, values[column])
	return self


## Creates an entity with [param components] (component name to its values) when applied.
func spawn(components: Dictionary) -> Delta:
	spawns.append(components)
	return self


func despawn(id: int) -> Delta:
	despawns.append(id)
	return self


## Takes [param component] from [param id] when applied, leaving the entity's other components.
func remove(component: StringName, id: int) -> Delta:
	removals.append([component, id])
	return self


func emit(event: WorldEvent) -> Delta:
	events.append(event)
	return self


## Appends everything in [param other] after this delta's own changes.
func merge(other: Delta) -> Delta:
	if other == null:
		return self
	_components.append_array(other._components)
	_ids.append_array(other._ids)
	_columns.append_array(other._columns)
	_values.append_array(other._values)
	spawns.append_array(other.spawns)
	despawns.append_array(other.despawns)
	removals.append_array(other.removals)
	events.append_array(other.events)
	return self


func is_empty() -> bool:
	return _ids.is_empty() and spawns.is_empty() and despawns.is_empty() \
		and removals.is_empty() and events.is_empty()


## The writes, as parallel arrays, for [method World.apply].
func write_count() -> int:
	return _ids.size()


func write_at(index: int) -> Array:
	return [_components[index], _ids[index], _columns[index], _values[index]]
