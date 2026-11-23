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
## Counts every change to the store, so a value derived from it can tell whether it is still
## current.
var version := 0
## Counts the rows taken out, so a view can tell an entity left even when another came in.
var removals := 0

var _row := {}
var _sorted := PackedInt64Array()
var _sorted_valid := false
var _defaults := {}
var _bools := {}


## [param defaults] maps each column to its default value; the value's type picks the column's
## storage: float, int, bool, Vector2, Vector3, and Color get packed arrays, anything else a
## plain [Array].
func _init(p_name: StringName, defaults: Dictionary) -> void:
	name = p_name
	for field: StringName in defaults:
		var value: Variant = defaults[field]
		_defaults[field] = value
		match typeof(value):
			TYPE_FLOAT:
				columns[field] = PackedFloat64Array()
			TYPE_INT:
				columns[field] = PackedInt64Array()
			TYPE_BOOL:
				columns[field] = PackedByteArray()
				_bools[field] = true
			TYPE_VECTOR2:
				columns[field] = PackedVector2Array()
			TYPE_VECTOR3:
				columns[field] = PackedVector3Array()
			TYPE_COLOR:
				columns[field] = PackedColorArray()
			_:
				columns[field] = []


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
		for field: StringName in values:
			set_value(id, field, values[field])
		return
	_row[id] = ids.size()
	ids.append(id)
	_sorted_valid = false
	version += 1
	for field: StringName in columns:
		var value: Variant
		if values.has(field):
			value = values[field]
		else:
			value = _defaults[field]
			# A container default is the row's own copy, not one shared by every row.
			if value is Array or value is Dictionary:
				value = value.duplicate()
		if _bools.has(field):
			value = 1 if value else 0
		columns[field].append(value)


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
		for field: StringName in columns:
			columns[field][row] = columns[field][last]
	ids.resize(last)
	for field: StringName in columns:
		columns[field].resize(last)
	_row.erase(id)
	_sorted_valid = false
	version += 1
	removals += 1


func get_value(id: int, field: StringName) -> Variant:
	var row: int = _row.get(id, -1)
	if row < 0:
		return _defaults.get(field)
	var value: Variant = columns[field][row]
	return value == 1 if _bools.has(field) else value


func set_value(id: int, field: StringName, value: Variant) -> void:
	var row: int = _row.get(id, -1)
	if row < 0:
		return
	if _bools.has(field):
		value = 1 if value else 0
	columns[field][row] = value
	version += 1


## The column's array, shared, for systems to read in a loop. Reading only: writes go through a
## [Delta].
func column(column_name: StringName) -> Variant:
	return columns[column_name]


## Replaces [param column_name] whole with [param values], one per row in row order: how a system
## that computed a fresh column hands it over.
func replace_column(column_name: StringName, values: Variant) -> void:
	columns[column_name] = values
	version += 1


## The rows' ids in ascending order, for systems whose output must not depend on row order. Kept
## between calls and rebuilt only after an entity is added or removed; read it, do not change it.
func sorted_ids() -> PackedInt64Array:
	if not _sorted_valid:
		_sorted = ids.duplicate()
		_sorted.sort()
		_sorted_valid = true
	return _sorted
