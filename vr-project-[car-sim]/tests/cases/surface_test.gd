extends TestCase
## Road surfaces: a road and a junction pad are solid asphalt, flush with their drawn asphalt, so a
## wheel's ray down onto a road finds the asphalt's grip and onto the grass beside it the ground's.

## A straight road along -Z from z = 0 to the crossroads, whose centre is CROSS_Z.
const ROAD_END := -40.0
const CROSS_Z := ROAD_END - 7.5
## Off the road and its 2 m pavements, on the grass.
const GRASS_X := 20.0
const ENVIRONMENT := preload("res://scenarios/kit/road_environment.tscn")


func run() -> void:
	_test_type()
	await _test_baked(_map())


func _test_type() -> void:
	var asphalt := BodyType.of(&"asphalt")
	var ground := BodyType.of(&"ground")
	expect(asphalt != null and asphalt.layer == Layers.WORLD and is_equal_approx(asphalt.friction,
		1.0) and not asphalt.judged(), "the asphalt type is on the world layer, full grip, unjudged")
	expect(ground.friction < asphalt.friction, "the grass grips less than the asphalt")
	var segment := RoadSegment.new()
	segment.curve = Curve3D.new()
	segment.curve.add_point(Vector3.ZERO)
	segment.curve.add_point(Vector3(0, 0, -10))
	root.add_child(segment)
	var body := segment.surface_body()
	var top := -INF
	if body:
		for child in body.get_children():
			var shape := child as CollisionShape3D
			if shape and shape.shape is ConvexPolygonShape3D:
				for point in (shape.shape as ConvexPolygonShape3D).points:
					top = maxf(top, point.y)
	expect(body != null and body.collision_layer == Layers.WORLD
		and is_equal_approx(top, RoadKit.LIFT),
		"a road's asphalt is one solid body whose top is the drawn asphalt")
	segment.surface = StandardMaterial3D.new()
	segment.rebuild()
	expect(segment.surface_body() != null, "a road in a plain surface is solid asphalt too")
	segment.free()


func _map() -> PackedScene:
	var road_map := RoadMap.new()
	road_map.name = "Surfaces"
	var environment := ENVIRONMENT.instantiate()
	environment.name = "Environment"
	var spawn := MapSpawn.new()
	spawn.position = Vector3(LANE_X, 0, -5)
	var segment := RoadSegment.new()
	segment.name = "Road"
	segment.curve = Curve3D.new()
	segment.curve.add_point(Vector3.ZERO)
	segment.curve.add_point(Vector3(0, 0, ROAD_END))
	var junction := RoadJunction.new()
	junction.name = "Crossroads"
	junction.arm_length = 4.0
	junction.position = Vector3(0, 0, CROSS_Z)
	for node: Node in [environment, spawn, segment, junction]:
		road_map.add_child(node)
		node.owner = road_map
	var packed := PackedScene.new()
	packed.pack(road_map)
	road_map.free()
	return packed


func _test_baked(map: PackedScene) -> void:
	var runner: ExamRunner = RUNNER.instantiate()
	runner.print_results = false
	runner.scenario_scene = null
	root.add_child(runner)
	runner.load_map(map)
	await frames(2)
	var space := runner.get_world_3d().direct_space_state
	var cases := [[Vector3(-LANE_X, 0, -20), &"asphalt", "the road"],
		[Vector3(LANE_X, 0, CROSS_Z), &"asphalt", "the junction's square"],
		[Vector3(-6.0, 0, CROSS_Z + LANE_X), &"asphalt", "a junction arm"],
		[Vector3(GRASS_X, 0, -20), &"ground", "the grass"]]
	for c: Array in cases:
		var hit := _down(space, c[0])
		var type := BodyType.of(c[1])
		var body := hit.get(&"collider") as StaticBody3D
		var friction := body.physics_material_override.friction \
			if body and body.physics_material_override else -1.0
		var height: float = hit.position.y if hit else INF
		var flush := RoadKit.LIFT if c[1] == &"asphalt" else 0.0
		expect(body != null and body.collision_layer == type.layer
			and is_equal_approx(friction, type.friction) and absf(height - flush) < 0.001,
			"a ray down onto %s hits %s, friction %.2f, at its drawn height (hit %s, friction %.2f, y %.3f)"
			% [c[2], c[1], type.friction, body.name if body else "nothing", friction, height])
	if runner.session.is_running():
		runner.session.abort()
	runner.queue_free()
	await process_frame


## What a ray straight down onto [param point] from 2 m above hits first, on the world layer.
func _down(space: PhysicsDirectSpaceState3D, point: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(point + Vector3.UP * 2.0,
		point + Vector3.DOWN, Layers.WORLD)
	return space.intersect_ray(query)
