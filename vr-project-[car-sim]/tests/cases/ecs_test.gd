extends TestCase
## The ECS core: component stores, the world and its deltas, the runner's tick order, and the
## shared geometry.


class Doubler extends PipelinedSystem:
	var _work := {}
	var _result: Delta

	func begin(world: World, _dt: float) -> void:
		# Copies what it needs; the work below reads only the copy.
		var s := world.store(&"counter")
		_work = {}
		for row in s.size():
			_work[s.ids[row]] = s.column(&"value")[row]
		_result = null

	func finish() -> Delta:
		if _work.is_empty():
			return null
		var d := Delta.new()
		for id: int in _work:
			d.write(&"counter", id, &"value", _work[id] * 2)
		d.emit(WorldEvent.new(&"doubled"))
		_work = {}
		return d


func run() -> void:
	_test_store()
	_test_world_apply()
	_test_runner_order()
	_test_geo()


func _test_store() -> void:
	var s := ComponentStore.new(&"pose", {at = Vector2.ZERO, speed = 0.0, lane = 0,
		parked = false, name = &""})
	s.add(10, {at = Vector2(1, 2), speed = 3.0})
	s.add(11, {lane = 4, parked = true})
	s.add(12, {name = &"van"})
	expect(s.size() == 3 and s.get_value(10, &"at") == Vector2(1, 2)
		and s.get_value(11, &"speed") == 0.0 and s.get_value(11, &"parked") == true
		and s.get_value(12, &"name") == &"van",
		"a store keeps each entity's values, with defaults for the columns not given")
	expect(s.column(&"speed") is PackedFloat64Array and s.column(&"at") is PackedVector2Array
		and s.column(&"parked") is PackedByteArray and s.column(&"name") is Array,
		"columns are packed arrays by type, plain arrays otherwise")
	s.remove(10)
	expect(s.size() == 2 and not s.has(10) and s.get_value(12, &"name") == &"van"
		and s.get_value(11, &"lane") == 4 and s.row_of(12) == 0,
		"removing an entity moves the last row into its place and keeps the others' values")
	s.set_value(12, &"parked", true)
	expect(s.get_value(12, &"parked") == true and s.sorted_ids() == PackedInt64Array([11, 12]),
		"values are written in place, and ids sort for a stable order")


func _test_world_apply() -> void:
	var world := World.new()
	world.define(&"counter", {value = 0})
	world.define(&"tag", {label = &""})
	var a := world.spawn({counter = {value = 1}, tag = {label = &"a"}})
	var b := world.spawn({counter = {value = 2}})
	expect(a != b and world.has(&"tag", a) and not world.has(&"tag", b),
		"entities get distinct ids and only the components they are given")
	world.begin_tick(0.5)
	var d := Delta.new()
	d.write(&"counter", a, &"value", 5).write(&"counter", a, &"value", 6)
	d.remove(&"tag", a).despawn(b).spawn({counter = {value = 9}})
	d.emit(WorldEvent.new(&"changed", a, {why = &"test"}))
	expect(world.get_value(&"counter", a, &"value") == 1,
		"building a delta does not change the world")
	world.apply(d)
	expect(world.get_value(&"counter", a, &"value") == 6 and not world.has(&"tag", a)
		and not world.has(&"counter", b) and world.store(&"counter").size() == 2,
		"applying writes in order, then removes, despawns, and spawns")
	expect(world.events.size() == 1 and world.events[0].kind == &"changed"
		and world.events[0].time == 0.5 and world.events[0].get_data(&"why") == &"test",
		"events are collected in order and stamped with the world's time")
	world.begin_tick(0.5)
	expect(world.events.is_empty() and world.tick == 2 and world.time == 1.0,
		"a new tick clears the events and advances the clock")


func _test_runner_order() -> void:
	var runner := WorldRunner.new()
	var world := runner.world
	world.define(&"counter", {value = 0})
	var id := world.spawn({counter = {value = 1}})
	var seen: Array = []
	runner.add_input(func(w: World, _dt: float) -> Delta:
		seen.append("input %d" % w.get_value(&"counter", id, &"value"))
		return Delta.new().write(&"counter", id, &"value", w.get_value(&"counter", id, &"value") + 1))
	# Two systems reading the same value: both see the input's result, neither sees the other's.
	runner.add_system(func(w: World, _dt: float) -> Delta:
		var v: int = w.get_value(&"counter", id, &"value")
		seen.append("first %d" % v)
		return Delta.new().write(&"counter", id, &"value", v + 10))
	runner.add_system(func(w: World, _dt: float) -> Delta:
		var v: int = w.get_value(&"counter", id, &"value")
		seen.append("second %d" % v)
		return Delta.new().write(&"counter", id, &"value", v + 100))
	runner.add_pipelined(Doubler.new())
	var published: Array = []
	runner.events_emitted.connect(func(events: Array[WorldEvent]) -> void:
		published.append(events.size()))
	runner.add_view(func(w: World) -> void:
		seen.append("view %d" % w.get_value(&"counter", id, &"value")))
	runner.step(1.0 / 60.0)
	expect(seen == ["input 1", "first 2", "second 2", "view 102"],
		"inputs run first, systems all read the same world and apply in order, views run last")
	seen.clear()
	runner.step(1.0 / 60.0)
	expect(seen[0] == "input 204" and published == [1],
		"a pipelined system's result lands first in the next tick, with its events")
	runner.free()


func _test_geo() -> void:
	var box := Transform3D(Basis(Vector3.UP, 0.4), Vector3(3, 1, -2))
	var half := Vector3(1.0, 1.0, 2.5)
	var inside := box * Vector3(0.9, 0.0, -2.4)
	var outside := box * Vector3(1.2, 0.0, 0.0)
	expect(Geo.point_in_box(box, half, inside) and not Geo.point_in_box(box, half, outside)
		and Geo.point_in_box(box, half, outside, 0.3),
		"a point is in a turned box by its own axes, and a margin grows it on the ground")
	var car := Transform3D(Basis(Vector3.UP, 1.2), box * Vector3(0, -1, -3.4))
	expect(Geo.body_in_box(car, Vector2(1.8, 4.2), 1.5, box, half),
		"a car body whose centre is outside a box still overlaps it with its length")
	var far := Transform3D(Basis(), box * Vector3(0, -1, -6.0))
	expect(not Geo.body_in_box(far, Vector2(1.8, 4.2), 1.5, box, half),
		"and a body clear of the box does not")
	var high := Transform3D(Basis(), box.origin + Vector3.UP * 5.0)
	expect(not Geo.body_in_box(high, Vector2(1.8, 4.2), 1.5, box, half),
		"a body above the box does not overlap it")
	var rect := Transform3D(Basis(Vector3.UP, 0.3), Vector3(5, 0, 5))
	var points := Geo.ground_rect(rect, 1.0, 2.0)
	expect(is_zero_approx(Geo.overhang(rect, Vector2(1.0, 2.0), points))
		and is_equal_approx(Geo.overhang(rect, Vector2(0.6, 2.0), points), 0.2),
		"a rectangle's own corners do not overhang it, and overhang a narrower one by the difference")
	var angles := Geo.facing_angles(Vector3(0, 0, -1), Vector3(1, 0, -1))
	expect(is_equal_approx(angles.x, 45.0) and is_equal_approx(angles.y, 135.0),
		"facing angles measure against a direction and its reverse")
	var hit := Geo.crossing(Vector2(0, 0), Vector2(2, 0), Vector2(1, -1), Vector2(1, 1))
	expect(is_equal_approx(hit.x, 0.5) and is_equal_approx(hit.y, 0.5)
		and Geo.crossing(Vector2(0, 0), Vector2(0.5, 0), Vector2(1, -1), Vector2(1, 1)).x < 0.0,
		"a move crosses a segment at its fractions along both, and a short move does not")
