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
## Each spawn's entity, in the order of [member spawns]: one [method World.create] reserved, or 0
## for a new one.
var spawn_ids := PackedInt64Array()
var despawns := PackedInt64Array()
## Each whole column written: [component, ids (row order the values follow), column, values].
var columns: Array = []
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


## Writes a whole column of [param component]: [param values] holds one value per entity of
## [param ids], in that order. When the store's rows are still those ids in that order, the column
## is swapped in whole; otherwise each value is written to its entity.
func write_column(component: StringName, ids: PackedInt64Array, column: StringName,
		values: Variant) -> Delta:
	columns.append([component, ids, column, values])
	return self


## Creates an entity with [param components] (component name to its values) when applied: entity
## [param id] when given, one reserved with [method World.create], else a new one.
func spawn(components: Dictionary, id := 0) -> Delta:
	spawns.append(components)
	spawn_ids.append(id)
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
	columns.append_array(other.columns)
	spawns.append_array(other.spawns)
	spawn_ids.append_array(other.spawn_ids)
	despawns.append_array(other.despawns)
	removals.append_array(other.removals)
	events.append_array(other.events)
	return self


func is_empty() -> bool:
	return _ids.is_empty() and columns.is_empty() and spawns.is_empty() and despawns.is_empty() \
		and removals.is_empty() and events.is_empty()


## The single writes, as parallel arrays, for [method World.apply] to read without copying.
func write_count() -> int:
	return _ids.size()


func write_components() -> Array[StringName]:
	return _components


func write_ids() -> PackedInt64Array:
	return _ids


func write_columns() -> Array[StringName]:
	return _columns


func write_values() -> Array:
	return _values
