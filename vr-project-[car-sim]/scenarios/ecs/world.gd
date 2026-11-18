class_name World
extends RefCounted
## The simulation's data, detached from nodes and rendering. An entity is an int; its data is the
## rows it has in the [ComponentStore]s, one per component. Systems read the world and return a
## [Delta]; only [method apply] changes it, so a tick's systems all see the same state and their
## results are applied in a fixed order. Views and the HUD read the world after a tick; nothing
## outside the shell writes it.

## Physics ticks the world has run.
var tick := 0
## Simulation seconds.
var time := 0.0
## The events of the last tick, in the order they were applied.
var events: Array[WorldEvent] = []
## Data shared by the whole simulation that no tick changes, built when a scenario is baked: the
## marking index, the lanes, the scenario's steps. Systems read it freely.
var resources := {}

var _next_id := 1
var _stores := {}


## Declares [param component] with its columns and their defaults (see [ComponentStore]); returns
## the existing store when it is already declared.
func define(component: StringName, defaults: Dictionary) -> ComponentStore:
	if _stores.has(component):
		return _stores[component]
	var store := ComponentStore.new(component, defaults)
	_stores[component] = store
	return store


func store(component: StringName) -> ComponentStore:
	return _stores.get(component)


func has_component(component: StringName) -> bool:
	return _stores.has(component)


## A new entity id with no components yet.
func create() -> int:
	var id := _next_id
	_next_id += 1
	return id


## A new entity with [param components]: component name to its values.
func spawn(components: Dictionary) -> int:
	var id := create()
	for component: StringName in components:
		_stores[component].add(id, components[component])
	return id


func despawn(id: int) -> void:
	for component: StringName in _stores:
		_stores[component].remove(id)


func has(component: StringName, id: int) -> bool:
	var s: ComponentStore = _stores.get(component)
	return s != null and s.has(id)


func get_value(component: StringName, id: int, column: StringName) -> Variant:
	return _stores[component].get_value(id, column)


## Applies [param delta]: whole columns, then single writes, then removals, despawns, and spawns,
## in the order the delta holds them; its events are appended to [member events], stamped with the
## world's time.
func apply(delta: Delta) -> void:
	if delta == null:
		return
	for written: Array in delta.columns:
		var target: ComponentStore = _stores.get(written[0])
		if target == null:
			continue
		var ids: PackedInt64Array = written[1]
		if target.ids == ids:
			target.replace_column(written[2], written[3])
		else:
			var values: Variant = written[3]
			for k in ids.size():
				target.set_value(ids[k], written[2], values[k])
	for i in delta.write_count():
		var w := delta.write_at(i)
		var s: ComponentStore = _stores.get(w[0])
		if s:
			s.set_value(w[1], w[2], w[3])
	for removal: Array in delta.removals:
		var s: ComponentStore = _stores.get(removal[0])
		if s:
			s.remove(removal[1])
	for id in delta.despawns:
		despawn(id)
	for components in delta.spawns:
		spawn(components)
	for event in delta.events:
		event.time = time
		events.append(event)


## Starts a tick: advances the clock and clears the last tick's events.
func begin_tick(dt: float) -> void:
	tick += 1
	time += dt
	events = []
