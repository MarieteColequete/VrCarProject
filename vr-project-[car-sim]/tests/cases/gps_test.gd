extends TestCase
## The dashboard's GPS: the heading-up projection, the metres left along a way, the tablet's place
## on the dash, and each scenario's map, way and goal as the tablet reads them, free drive too.

const SAMPLE_TOWN := preload("res://maps/sample_town/sample_town.tscn")


func run() -> void:
	_test_heading_up()
	_test_along()
	await _test_scenarios()
	await _test_free_drive()


func _near(a: Vector2, b: Vector2) -> bool:
	return a.distance_to(b) < 0.01


func _test_heading_up() -> void:
	var car := Vector2(10.0, 20.0)
	var anchor := Vector2(100.0, 100.0)
	var north := GpsMap.heading_up(car, Vector2(0.0, -1.0), 2.0, anchor)
	expect(_near(north * car, anchor) and _near(north * Vector2(10.0, 10.0), Vector2(100.0, 80.0))
		and _near(north * Vector2(12.0, 20.0), Vector2(104.0, 100.0)),
		"facing north, the car sits on the anchor, ahead is up and its right is right")
	var east := GpsMap.heading_up(car, Vector2(1.0, 0.0), 2.0, anchor)
	expect(_near(east * car, anchor) and _near(east * Vector2(20.0, 20.0), Vector2(100.0, 80.0))
		and _near(east * Vector2(10.0, 22.0), Vector2(104.0, 100.0)),
		"turned east, the map turns under it: east is up and south is right")


func _test_along() -> void:
	var way := PackedVector2Array([Vector2(0, 0), Vector2(0, -10), Vector2(10, -10)])
	var at := GpsMap.along(way, Vector2(1.0, -5.0))
	expect(is_equal_approx(at.left, 15.0) and at.index == 0 and _near(at.point, Vector2(0, -5)),
		"halfway along the first leg, 15 m are left: %.2f" % at.left)
	expect(is_equal_approx(GpsMap.along(way, Vector2(12.0, -9.0)).left, 0.0),
		"past the end, none are left")


func _test_scenarios() -> void:
	for definition in ScenarioCatalogue.main().scenarios:
		var runner := spawn_runner(definition.load_scene())
		await process_frame
		var car: Node3D = runner.car
		var tablet: CarTablet = car.get(&"tablet")
		var what := String(definition.id)
		expect(tablet != null and tablet.map != null and tablet.map.roads.size() >= 3,
			"%s: the tablet shows the map's roads" % what)
		if tablet == null or tablet.map == null:
			runner.queue_free()
			continue
		if definition == ScenarioCatalogue.main().scenarios[0]:
			_test_placement(car, tablet)
		var steps := runner.scenario.get_steps()
		expect(tablet.title == (steps[0].title if not steps.is_empty() else definition.title),
			"%s: the bar names the task: %s" % [what, tablet.title])
		var goal := tablet.map.goal_for(tablet.step)
		if goal.is_empty():
			expect(tablet.left < 0.0, "%s: no goal, no distance" % what)
			runner.queue_free()
			continue
		var way := tablet.map.route_for(tablet.step)
		var start := Vector2(car.global_position.x, car.global_position.z)
		expect(way.size() >= 2 and way[0].distance_to(start) < 3.0
			and way[way.size() - 1].distance_to(goal.centre) <= goal.radius,
			"%s: its way runs from the start to the goal" % what)
		var forward := -car.global_basis.z
		tablet.follow(1.0, car.global_position, forward, 0.0)
		var before := tablet.left
		tablet.follow(1.0, car.global_position + forward * 10.0, forward, 0.0)
		expect(before > 10.0 and absf(before - tablet.left - 10.0) < 0.5 and tablet.draws > 0,
			"%s: 10 m along, 10 m less to go: %.1f to %.1f m" % [what, before, tablet.left])
		runner.queue_free()
		await process_frame


func _test_placement(car: Node3D, tablet: CarTablet) -> void:
	var model: PlayerCarModel = car.get(&"model")
	var eye: Vector3 = car.get(&"driver_view").position
	var facing := tablet.transform.basis.z.normalized()
	expect(tablet.get_parent() == model.cabin
		and facing.dot((eye - tablet.position).normalized()) > cos(deg_to_rad(5.0)),
		"the tablet is on the dash, its screen turned to the driver's eye")
	var cluster_end := (PlayerCarModel.CLUSTER.box as AABB).end.x * model.fit
	var left_edge := tablet.transform * Vector3(-CarTablet.SIZE.x / 2.0 - CarTablet.BEZEL, 0, 0)
	expect(left_edge.x > cluster_end,
		"right of the instruments: %.2f m past them" % (left_edge.x - cluster_end))
	var mount := PlayerCarModel.TABLET_MOUNT * model.fit
	var base := tablet.transform * (tablet.get_node("Mount") as Node3D).position
	var held := tablet.position - mount
	expect(base.distance_to(mount) < 0.001 and held.z > 0.15 and absf(held.x) < 0.001,
		"held out on its arm straight back from its mount on the dash, %.2f m" % held.length())


func _test_free_drive() -> void:
	var runner := spawn_runner()
	await process_frame
	runner.load_map(SAMPLE_TOWN)
	await process_frame
	await process_frame
	var tablet: CarTablet = runner.car.get(&"tablet")
	expect(tablet != null and tablet.title == "Free drive" and tablet.left < 0.0
		and tablet.map.roads.size() >= 3,
		"in free drive the tablet shows the town's roads, with no way and no goal")
	runner.queue_free()
	await process_frame
