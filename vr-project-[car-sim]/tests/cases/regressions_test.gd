extends TestCase
## Faults the code-quality pass found, each held fixed: Map Kit's problem list building no nodes
## until a fix is applied; the land under a moved road built again from what the road reaches; a
## road user replaced between two draws leaving the traffic view; and the car's contacts written
## only when they change, so the car is read once a tick.


func run() -> void:
	_test_problems_build_nothing()
	await _test_moved_road()
	await _test_replaced_road_user()
	_test_contacts_written_on_change()


func _test_problems_build_nothing() -> void:
	var map: RoadMap = load(MapKitTools.BASE).instantiate()
	var road := RoadSegment.new()
	road.name = "Bare"
	road.curve = straight(30.0)
	map.add_child(road)
	var shape := TerrainShape.new()
	map.add_child(shape)
	MapKitTools.problems(map)
	var before := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var labels: Array = []
	for i in 20:
		labels = MapKitTools.problems(map).filter(func(p: Dictionary) -> bool:
			return p.fix != null).map(func(p: Dictionary) -> String: return p.fix_label)
	var after := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	expect(after - before == 0 and labels.has("Generate") and labels.has("Add terrain"),
		"listing a map's problems 20 times builds no nodes (%d made), its fixes still offered: %s"
		% [after - before, labels])
	map.free()


func _test_moved_road() -> void:
	var map := RoadMap.new()
	var terrain := Terrain.new()
	terrain.size = Vector2(120, 120)
	map.add_child(terrain)
	var hill := TerrainShape.new()
	hill.height = 4.0
	hill.radius = 30.0
	hill.falloff = 20.0
	map.add_child(hill)
	var road := RoadSegment.new()
	road.curve = straight(40.0)
	road.position = Vector3(-20, 0, 0)
	map.add_child(road)
	root.add_child(map)
	await process_frame
	terrain.rebuild()
	var was := terrain.piece_area(road)
	road.position = Vector3(20, 0, 0)
	var now := terrain.piece_area(road)
	terrain.rebuild_area(was.merge(now))
	var patched := terrain.field().heights.duplicate()
	terrain.rebuild()
	var worst := 0.0
	for k in patched.size():
		worst = maxf(worst, absf(patched[k] - terrain.field().heights[k]))
	expect(now.has_point(Vector2(20, 0)) and not now.has_point(Vector2(-20, 0)) and worst < 0.0001,
		"a moved road's land is built again where it was and is, the same as built whole: "
		+ "%.5f m off" % worst)
	map.queue_free()
	await process_frame


func _test_replaced_road_user() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var world := World.new()
	Simulation.empty_world(world)
	var view := TrafficView.new(holder, 4)
	var first := world.spawn({agent = {position = Vector3(0, 0, -20)}})
	view.draw(world)
	# One leaves and another comes in before the next draw: the count stays the same.
	world.despawn(first)
	world.spawn({agent = {position = Vector3(5, 0, -20)}})
	view.draw(world)
	var drawn := 0
	for key: String in view.counts():
		drawn += int(view.counts()[key])
	expect(drawn == 1, "a road user replaced between two draws leaves the view: %d drawn" % drawn)
	view.clear()
	holder.queue_free()
	await process_frame


func _test_contacts_written_on_change() -> void:
	var world := World.new()
	Simulation.empty_world(world)
	world.spawn({vehicle = {transform = Transform3D.IDENTITY}})
	var d := Detection.contacts(world, 0.1)
	expect(d.write_count() == 0, "nothing touching, as before: the car's contacts are not written")

