extends TestCase
## Solid things: the body types and their layers, a road's pavement and a drawn kerb's wall, what
## the bake judges, and the player's car driven for real (its physics, not moved by the test) into
## a kerb, along one, and into a house.

const HOUSE := "res://assets/kenney/city_kit_suburban/building-type-a.glb"
const PATH := "res://assets/kenney/city_kit_suburban/path-long.glb"
const PARKED := "res://assets/kenney/car_kit/sedan.glb"
## Where the kerb's face is: the edge of the map's road, one 3.5 m lane each side of x = 0.
const KERB_X := 3.5
const HOUSE_Z := -30.0


func run() -> void:
	_test_types()
	_test_kerb_wall()
	var map := _map()
	await _test_bake(map)
	await _test_head_on(map)
	await _test_along(map)
	await _test_house(map)


func _test_types() -> void:
	var expected := {ground = Layers.WORLD, pavement = Layers.PAVEMENT,
		obstacle = Layers.OBSTACLE, vehicle = Layers.TRAFFIC, pedestrian = Layers.PEDESTRIAN,
		player = Layers.VEHICLE}
	for kind: String in expected:
		var type := BodyType.of(StringName(kind))
		expect(type != null and type.layer == expected[kind], "the %s type is on its layer" % kind)
	var judged := [&"obstacle", &"vehicle", &"pedestrian"]
	for kind: String in expected:
		var type := BodyType.of(StringName(kind))
		expect(type.judged() == (StringName(kind) in judged),
			"the %s type is judged only if its layer is" % kind)
	var player := BodyType.of(&"player")
	expect((player.mask & Layers.PAVEMENT) != 0 and (player.mask & Layers.OBSTACLE) != 0
		and (player.mask & Layers.TRAFFIC) != 0, "the player's car collides with pavements, obstacles and traffic")

	var body := StaticBody3D.new()
	BodyType.of(&"obstacle").apply(body)
	expect(body.collision_layer == Layers.OBSTACLE and body.physics_material_override != null,
		"a type gives a body its layer and surface")
	body.free()


func _test_kerb_wall() -> void:
	var kerb := RoadMarking.new()
	kerb.kind = RoadMarking.Kind.KERB
	kerb.curve = Curve3D.new()
	kerb.curve.add_point(Vector3(0, 0, 0))
	kerb.curve.add_point(Vector3(0, 0, -10))
	root.add_child(kerb)
	var wall := _body_in(kerb)
	expect(wall != null and wall.collision_layer == Layers.PAVEMENT,
		"a drawn kerb line is a solid wall on the pavement layer")
	kerb.free()

	var segment := _segment()
	root.add_child(segment)
	var pavement := segment.pavement_body()
	var top := -INF
	if pavement:
		for child in pavement.get_children():
			var shape := child as CollisionShape3D
			if shape and shape.shape is ConvexPolygonShape3D:
				for point in (shape.shape as ConvexPolygonShape3D).points:
					top = maxf(top, point.y)
	expect(pavement != null and pavement.collision_layer == Layers.PAVEMENT
		and is_equal_approx(top, RoadMarking.KERB_HEIGHT),
		"a road's pavements are one solid body on the pavement layer, kerb high")
	segment.kerbs = false
	segment.rebuild()
	expect(segment.pavement_body() == null, "a road without kerbs has no pavement body")
	segment.free()


## A straight road along -Z from z = 0, the car starting in its right-hand lane, a house ahead in
## that lane, a looks-only path on the way to it, and a parked car in the other lane.
func _map() -> PackedScene:
	var road_map := RoadMap.new()
	road_map.name = "Solids"
	var spawn := MapSpawn.new()
	spawn.position = Vector3(LANE_X, 0, -5)
	var segment := _segment()
	var house := _asset(HOUSE, Vector3(LANE_X, 0, HOUSE_Z), BodyType.of(&"obstacle"))
	var path_asset := _asset(PATH, Vector3(LANE_X, 0, -15), null)
	var parked := _asset(PARKED, Vector3(-LANE_X, 0, -20), BodyType.of(&"vehicle"))
	for node: Node in [spawn, segment, house, path_asset, parked]:
		road_map.add_child(node)
		node.owner = road_map
	root.add_child(road_map)
	segment.generate_lanes()
	segment.generate_markings()
	root.remove_child(road_map)
	var packed := PackedScene.new()
	packed.pack(road_map)
	road_map.free()
	return packed


func _test_bake(map: PackedScene) -> void:
	var runner := _runner(map)
	await process_frame
	var obstacles := runner.world().store(Schema.OBSTACLE)
	expect(obstacles.size() == 2,
		"the house and the parked car bake into obstacles; the pavements and the path do not")
	runner.queue_free()
	await process_frame


## Driven straight at the kerb, the front tyres stop against it, and that is hitting the kerb.
func _test_head_on(map: PackedScene) -> void:
	var ground_body := ground()
	var runner := _runner(map)
	await process_frame
	var car: Node3D = runner.car
	car.look_at(car.global_position + Vector3.RIGHT, Vector3.UP)
	car.reset_physics_interpolation()
	car.set(&"held_controls", {throttle = 1.0, select = "D"})
	await frames(120)
	var front := car.global_position.x + 1.3 + 0.325
	expect(car.global_position.x > LANE_X + 0.01 and front < KERB_X + 0.01,
		"driven at the kerb, the car moves until its tyres meet it, and no further")
	var r := _end(runner)
	ground_body.queue_free()
	expect(_count(r, &"kerb_mounted") == 1, _say("driving into the kerb is one kerb fault", r))
	await process_frame


## Steered into the kerb while driving along the road, the right-hand tyres stop against it.
func _test_along(map: PackedScene) -> void:
	var ground_body := ground()
	var runner := _runner(map)
	await process_frame
	var car: Node3D = runner.car
	car.set(&"held_controls", {throttle = 0.6, steer = -1.0, select = "D"})
	var furthest := -INF
	for i in 180:
		await physics_frame
		for z in [-1.3 - 0.325, -1.3 + 0.325, 1.3 - 0.325, 1.3 + 0.325]:
			furthest = maxf(furthest, (car.global_transform * Vector3(0.775 + 0.1, 0, z)).x)
	expect(furthest > KERB_X - 0.1 and furthest < KERB_X + 0.02,
		"steered into the kerb, the tyres reach it and stop against it")
	var r := _end(runner)
	ground_body.queue_free()
	expect(_count(r, &"kerb_mounted") >= 1, _say("steering into the kerb is a kerb fault", r))
	await process_frame


## Driven down the lane, the car crosses the looks-only path and stops against the house, which is
## a contact.
func _test_house(map: PackedScene) -> void:
	var ground_body := ground()
	var runner := _runner(map)
	await process_frame
	var car: Node3D = runner.car
	car.set(&"held_controls", {throttle = 1.0, select = "D"})
	await frames(360)
	var house_front := HOUSE_Z + KitModels.size_of(HOUSE).z / 2.0
	expect(car.global_position.z < -15.0, "the looks-only path does not stop the car")
	expect(car.global_position.z - 2.1 > house_front - 0.05,
		"the house stops the car: its body goes no further than the house's front")
	var r := _end(runner)
	ground_body.queue_free()
	expect(r.has_fault(&"contact_obstacle"), _say("driving into the house is a contact", r))
	await process_frame


func _segment() -> RoadSegment:
	var segment := RoadSegment.new()
	segment.name = "Road"
	segment.curve = Curve3D.new()
	segment.curve.add_point(Vector3(0, 0, 0))
	segment.curve.add_point(Vector3(0, 0, -60))
	return segment


func _asset(model: String, where: Vector3, type: BodyType) -> MapAsset:
	var asset := MapAsset.new()
	asset.name = model.get_file().get_basename().to_pascal_case()
	asset.model = model
	asset.body_type = type
	asset.position = where
	return asset


func _runner(map: PackedScene) -> ExamRunner:
	var runner: ExamRunner = RUNNER.instantiate()
	runner.print_results = false
	runner.scenario_scene = null
	root.add_child(runner)
	runner.load_map(map)
	return runner


func _end(runner: ExamRunner) -> ScenarioResult:
	if runner.session.is_running():
		runner.session.abort()
	var r := runner.session.result
	runner.queue_free()
	return r


func _count(r: ScenarioResult, id: StringName) -> int:
	var n := 0
	for fault in r.faults:
		if fault.def.id == id:
			n += 1
	return n


func _say(what: String, r: ScenarioResult) -> String:
	return "%s (faults: %s)" % [what, ", ".join(r.faults.map(func(f): return String(f.def.id)))]


func _body_in(node: Node) -> StaticBody3D:
	for child in node.get_children(true):
		if child is StaticBody3D:
			return child
	return null
