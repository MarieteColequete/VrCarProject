class_name ComponentStore
extends RefCounted
## One component of the [World]: a table whose rows are entities and whose columns are plain
## values, kept as packed arrays (structure of arrays) so systems read numbers rather than
## objects, and so loops can alias a column once and index it. Rows are dense: removing an entity
## moves the last row into its place, so the order of rows is not the order of entities; code
## that needs a stable order sorts by id.

## The component's name in the [World].
var name: StringName
## The entity of each row.
var ids := PackedInt64Array()
## Column name to its array of values, one per row.
var columns := {}

var _row := {}
var _defaults := {}
var _bools := {}


## [param defaults] maps each column to its default value; the value's type picks the column's
## storage: float, int, bool, Vector2 and Vector3 get packed arrays, anything else a plain
## [Array].
func _init(p_name: StringName, defaults: Dictionary) -> void:
	name = p_name
	for column: StringName in defaults:
		var value: Variant = defaults[column]
		_defaults[column] = value
		match typeof(value):
			TYPE_FLOAT:
				columns[column] = PackedFloat64Array()
			TYPE_INT:
				columns[column] = PackedInt64Array()
			TYPE_BOOL:
				columns[column] = PackedByteArray()
				_bools[column] = true
			TYPE_VECTOR2:
				columns[column] = PackedVector2Array()
			TYPE_VECTOR3:
				columns[column] = PackedVector3Array()
			_:
				columns[column] = []


func size() -> int:
	return ids.size()


func has(id: int) -> bool:
	return _row.has(id)


## The row of [param id], or -1 when the entity does not have this component.
func row_of(id: int) -> int:
	return _row.get(id, -1)


## Gives [param id] this component, with [param values] for the columns it names and the
## defaults for the rest. Replaces the values of an entity that already has it.
func add(id: int, values := {}) -> void:
	if _row.has(id):
		for column: StringName in values:
			set_value(id, column, values[column])
		return
	_row[id] = ids.size()
	ids.append(id)
	for column: StringName in columns:
		var value: Variant
		if values.has(column):
			value = values[column]
		else:
			value = _defaults[column]
			# A container default is the row's own copy, not one shared by every row.
			if value is Array or value is Dictionary:
				value = value.duplicate()
		if _bools.has(column):
			value = 1 if value else 0
		columns[column].append(value)


## Takes the component from [param id]; the last row moves into its place.
func remove(id: int) -> void:
	var row: int = _row.get(id, -1)
	if row < 0:
		return
	var last := ids.size() - 1
	if row != last:
		var moved := ids[last]
		ids[row] = moved
		_row[moved] = row
		for column: StringName in columns:
			columns[column][row] = columns[column][last]
	ids.resize(last)
	for column: StringName in columns:
		columns[column].resize(last)
	_row.erase(id)


func get_value(id: int, column: StringName) -> Variant:
	var row: int = _row.get(id, -1)
	if row < 0:
		return _defaults.get(column)
	var value: Variant = columns[column][row]
	return value == 1 if _bools.has(column) else value


func set_value(id: int, column: StringName, value: Variant) -> void:
	var row: int = _row.get(id, -1)
	if row < 0:
		return
	if _bools.has(column):
		value = 1 if value else 0
	columns[column][row] = value


## The column's array, shared, for systems to read in a loop. Reading only: writes go through a
## [Delta].
func column(column_name: StringName) -> Variant:
	return columns[column_name]


## The rows' ids in ascending order, for systems whose output must not depend on row order.
func sorted_ids() -> PackedInt64Array:
	var out := ids.duplicate()
	out.sort()
	return out
