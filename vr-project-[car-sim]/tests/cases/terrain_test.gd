extends TestCase
## Terrain and sloped roads: the height field's sampling, the terrain shapes, a heightmap, the
## corridor cut and filled under a road, the land's collider, a road on a grade, and draping a
## road on a hill no steeper than the grade allowed.

const GRADE := 0.1


func run() -> void:
	_test_sampling()
	_test_shapes()
	_test_heightmap()
	_test_corridor()
	await _test_collider()
	await _test_sloped_road()
	_test_drape()
	_test_add_terrain()


func _test_sampling() -> void:
	var field := HeightField.new(Vector2(-2, -2), 2.0, 3, 3)
	var values := [1.0, 2.0, 4.0, 0.0, -1.0, 3.0, 5.0, 2.0, 0.5]
	for k in values.size():
		field.set_point(k % 3, k / 3, values[k])
	var exact := true
	for k in values.size():
		var p := field.point(k % 3, k / 3)
		if not is_equal_approx(field.height_at(p.x, p.z), values[k]):
			exact = false
	expect(exact, "the field is exact at its grid points")
	expect(is_equal_approx(field.height_at(-1, -1), (1.0 + 2.0 + 0.0 - 1.0) / 4.0)
		and is_equal_approx(field.height_at(0, -2), 2.0) and is_equal_approx(field.height_at(1, 0),
		(-1.0 + 3.0) / 2.0), "between the points the height is bilinear")
	expect(is_equal_approx(field.height_at(-50, -50), 1.0),
		"beyond the field the height is its edge's")
	var flat := HeightField.new(Vector2.ZERO, 1.0, 4, 4, 2.0)
	expect(flat.normal_at(1.5, 1.5).is_equal_approx(Vector3.UP), "flat land's normal is straight up")


func _shape(kind: TerrainShape.Kind, height: float) -> TerrainShape:
	var shape := TerrainShape.new()
	shape.kind = kind
	shape.height = height
	shape.radius = 5.0
	shape.falloff = 10.0
	shape.size = Vector2(10, 30)
	return shape


## The land after [param shape], standing at [param at], acts on flat land at [param base].
func _shaped(shape: TerrainShape, at := Vector3.ZERO, base := 0.0) -> HeightField:
	var field := HeightField.covering(Vector2(100, 100), 1.0)
	field.heights.fill(base)
	shape.apply(field, Transform3D(Basis.IDENTITY, at))
	shape.free()
	return field


func _test_shapes() -> void:
	var hill := _shaped(_shape(TerrainShape.Kind.HILL, 5.0))
	expect(is_equal_approx(hill.height_at(0, 0), 5.0) and is_equal_approx(hill.height_at(4, 0), 5.0)
		and is_zero_approx(hill.height_at(16, 0)) and hill.height_at(10, 0) > 0.0
		and hill.height_at(10, 0) < 5.0,
		"a hill is its height at its centre, eases out, and is gone past its falloff")
	var valley := _shaped(_shape(TerrainShape.Kind.VALLEY, 3.0), Vector3(10, 0, 0), 1.0)
	expect(is_equal_approx(valley.height_at(10, 0), -2.0)
		and is_equal_approx(valley.height_at(10, 16), 1.0),
		"a valley lowers the land by its height at its centre, and not past its falloff")
	var ramp := _shaped(_shape(TerrainShape.Kind.RAMP, 3.0), Vector3(0, 1, 0))
	expect(is_equal_approx(ramp.height_at(0, 15), 1.0) and is_equal_approx(ramp.height_at(0, -15),
		4.0) and is_equal_approx(ramp.height_at(0, 0), 2.5) and is_zero_approx(ramp.height_at(16, 0)),
		"a ramp climbs its height along -Z from the node's own, and is gone past its falloff")
	var plateau := _shaped(_shape(TerrainShape.Kind.PLATEAU, 2.0), Vector3(0, 1, 0), 7.0)
	expect(is_equal_approx(plateau.height_at(0, 0), 3.0) and is_equal_approx(plateau.height_at(0,
		16), 7.0), "a plateau pulls the land to its height, and not past its falloff")


func _test_heightmap() -> void:
	var image := Image.create(3, 3, false, Image.FORMAT_RGB8)
	image.fill(Color.BLACK)
	image.set_pixel(2, 2, Color.WHITE)
	image.set_pixel(1, 1, Color(0.5, 0.5, 0.5))
	var terrain := Terrain.new()
	terrain.size = Vector2(20, 20)
	terrain.cell = 10.0
	terrain.heightmap = ImageTexture.create_from_image(image)
	terrain.heightmap_height = 10.0
	var land := terrain.land()
	expect(land.count_x == 3 and is_zero_approx(land.get_point(0, 0))
		and is_equal_approx(land.get_point(2, 2), 10.0)
		and absf(land.get_point(1, 1) - 5.0) < 0.05,
		"a heightmap's white stands its height above its black: %s" % [land.heights])
	terrain.free()


## A map with a terrain whose land is a plateau [param land_y] high, and a road along -Z through
## the origin at y = 0, of kit width 7 with 2 m pavements.
func _road_map(land_y: float) -> RoadMap:
	var map := RoadMap.new()
	map.name = "TerrainMap"
	var terrain := Terrain.new()
	terrain.name = "Terrain"
	terrain.size = Vector2(80, 80)
	var plateau := TerrainShape.new()
	plateau.kind = TerrainShape.Kind.PLATEAU
	plateau.height = land_y
	plateau.radius = 200.0
	var road := RoadSegment.new()
	road.name = "Road"
	road.curve = Curve3D.new()
	road.curve.add_point(Vector3(0, 0, 30))
	road.curve.add_point(Vector3(0, 0, -30))
	map.add_child(terrain)
	terrain.add_child(plateau)
	map.add_child(road)
	return map


func _test_corridor() -> void:
	var map := _road_map(2.0)
	var terrain := Terrain.of(map)
	var inner := 3.5 + RoadKit.PAVEMENT + Terrain.SHOULDER
	var outer := inner + terrain.road_blend
	var under := terrain.height_at(Vector3(0, 0, 0))
	var edge := terrain.height_at(Vector3(floorf(inner), 0, 5))
	var easing := terrain.height_at(Vector3(inner + terrain.road_blend / 2.0, 0, 5))
	var past := terrain.height_at(Vector3(outer + 1.0, 0, 5))
	expect(is_equal_approx(under, -Terrain.ROAD_SINK) and absf(edge + Terrain.ROAD_SINK) < 0.01,
		"the land lies 5 cm under the road out to its shoulder: %.3f, %.3f" % [under, edge])
	expect(easing > 0.0 and easing < 2.0 and is_equal_approx(past, 2.0),
		"and eases back to the land over the blend: %.3f, %.3f" % [easing, past])
	map.free()


func _test_collider() -> void:
	var map := RoadMap.new()
	var terrain := Terrain.new()
	terrain.size = Vector2(60, 60)
	var hill := TerrainShape.new()
	hill.kind = TerrainShape.Kind.HILL
	hill.height = 5.0
	hill.radius = 0.0
	hill.falloff = 30.0
	map.add_child(terrain)
	terrain.add_child(hill)
	terrain.position = Vector3(3, 1, -2)
	root.add_child(map)
	expect(terrain.ground_body() != null and terrain.ground_body().collision_layer
		== BodyType.of(&"ground").layer, "the land is solid ground")
	await frames(2)
	var space := map.get_world_3d().direct_space_state
	var worst := 0.0
	for point: Vector3 in [Vector3(3, 0, -2), Vector3(10.3, 0, 4.7), Vector3(-6.6, 0, -13.1),
			Vector3(20.5, 0, 9.25), Vector3(-24, 0, 20)]:
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(point + Vector3.UP * 50,
			point + Vector3.DOWN * 50))
		var want := terrain.height_at(point)
		worst = maxf(worst, absf((hit.position.y if hit else INF) - want))
	expect(worst <= 0.02, "a ray down onto the land meets it at the field's height: %.4f m" % worst)
	expect(terrain.get_child_count(true) > 1, "the land is drawn")
	map.queue_free()
	await process_frame


func _test_sloped_road() -> void:
	var road := RoadSegment.new()
	road.curve = Curve3D.new()
	road.curve.add_point(Vector3(0, 0, 0))
	road.curve.add_point(Vector3(0, 4, -40))
	root.add_child(road)
	var frames_up: Vector3 = road.frames()[3][2]
	expect(frames_up.is_equal_approx(Vector3(0, 1, GRADE).normalized())
		and (road.frames()[3][1] as Vector3).is_equal_approx(Vector3.RIGHT),
		"a frame's up is square to the grade and its right stays level")
	var mesh := (road.get_child(0, true) as MeshInstance3D).mesh
	var off := 0.0
	var tilted := true
	if mesh:
		var arrays := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		for k in vertices.size():
			var lift := vertices[k].y + GRADE * vertices[k].z
			# The kit's kerb faces reach as far below the ground as the kerb stands above it.
			off = maxf(off, maxf(-lift - RoadMarking.KERB_HEIGHT - 0.005,
				lift - RoadMarking.KERB_HEIGHT - 0.005))
			if absf(lift - RoadKit.LIFT) < 0.003 and normals[k].y > 0.9 \
					and absf(normals[k].z - GRADE) > 0.02:
				tilted = false
	expect(mesh != null and off <= 0.0 and tilted,
		"the road's mesh follows a 10%% grade, its asphalt facing square to it: %.3f m off" % off)
	var top_off := 0.0
	for child in road.surface_body().get_children():
		for point in ((child as CollisionShape3D).shape as ConvexPolygonShape3D).points:
			var lift := point.y + GRADE * point.z
			top_off = maxf(top_off, minf(absf(lift - RoadKit.LIFT), absf(lift + RoadKit.SINK)))
	expect(top_off < 0.001, "the asphalt's collider follows the grade: %.4f m off" % top_off)
	await frames(2)
	var space := road.get_world_3d().direct_space_state
	var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(1, 10, -20),
		Vector3(1, -10, -20)))
	expect(not hit.is_empty() and absf(hit.position.y - (2.0 + RoadKit.LIFT)) < 0.02,
		"a ray down meets the sloped asphalt at its drawn height")
	road.queue_free()
	await process_frame


func _test_drape() -> void:
	var map := RoadMap.new()
	var terrain := Terrain.new()
	terrain.name = "Terrain"
	terrain.size = Vector2(120, 120)
	var hill := TerrainShape.new()
	hill.kind = TerrainShape.Kind.HILL
	hill.height = 15.0
	hill.radius = 0.0
	hill.falloff = 25.0
	var road := RoadSegment.new()
	road.name = "Road"
	road.curve = Curve3D.new()
	road.curve.add_point(Vector3(0, 0, 50))
	road.curve.add_point(Vector3(0, 0, -50))
	var spawn := MapSpawn.new()
	spawn.position = Vector3(1.75, 0, 0)
	map.add_child(terrain)
	terrain.add_child(hill)
	map.add_child(road)
	map.add_child(spawn)
	for lane in road.make_lanes():
		road.add_child(lane)
	var edit := MapKitTools.drape(map)
	edit.apply(map)
	var steepest := 0.0
	var top := -INF
	var along := road.frames()
	for i in along.size() - 1:
		var a: Vector3 = along[i][0]
		var b: Vector3 = along[i + 1][0]
		steepest = maxf(steepest, absf(b.y - a.y) / Vector2(b.x - a.x, b.z - a.z).length())
		top = maxf(top, b.y)
	expect(top > 5.0 and steepest <= 0.12 + 0.001,
		"a draped road climbs the hill, %.1f m, no steeper than the grade: %.3f" % [top, steepest])
	var lane := road.get_child(0) as TrafficLane
	var lane_off := 0.0
	for point in lane.curve.get_baked_points():
		var on_road := 0.0
		var best := INF
		for frame: Array in along:
			var d := absf((frame[0] as Vector3).z - point.z)
			if d < best:
				best = d
				on_road = (frame[0] as Vector3).y
		lane_off = maxf(lane_off, absf(point.y - on_road))
	expect(lane_off < 0.25, "the road's lanes lie on it: %.3f m" % lane_off)
	expect(absf(spawn.position.y - top) < 0.3, "a spawn on the road stands on it")
	map.free()


func _test_add_terrain() -> void:
	var map: RoadMap = load(MapKitTools.BASE).instantiate()
	var edit := MapKitTools.add_terrain(map)
	edit.apply(map)
	var environment := map.get_node("Environment") as RoadEnvironment
	expect(Terrain.of(map) != null and not environment.ground
		and MapKitTools.add_terrain(map).is_empty(),
		"adding terrain turns the flat ground off, and is done once")
	map.free()
