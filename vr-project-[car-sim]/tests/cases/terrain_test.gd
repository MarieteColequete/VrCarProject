extends TestCase
## Terrain and sloped roads: the height field's sampling, the terrain shapes, a heightmap, the
## corridor cut and filled under a road and under a road drawn by hand, the land's collider, a road on a grade, and draping a
## road on a hill no steeper than the grade allowed. Then the editing: a shape's handles and its
## outline on the land, the land built again only where a shape changed (the same as built whole,
## and faster), and the Map Kit's shape edits.

const GRADE := 0.1


func run() -> void:
	_test_sampling()
	_test_shapes()
	_test_heightmap()
	_test_corridor()
	_test_drawn_road()
	await _test_collider()
	await _test_sloped_road()
	_test_drape()
	_test_add_terrain()
	_test_handles()
	_test_outline()
	await _test_partial_rebuild()
	await _test_shape_edits()


func _test_sampling() -> void:
	var field := HeightField.new(Vector2(-2, -2), 2.0, 3, 3)
	var values := [1.0, 2.0, 4.0, 0.0, -1.0, 3.0, 5.0, 2.0, 0.5]
	for k in values.size():
		@warning_ignore("integer_division")
		field.set_point(k % 3, k / 3, values[k])
	var exact := true
	for k in values.size():
		@warning_ignore("integer_division")
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


## The land after [param shape], standing at [param where], acts on flat land at [param base].
func _shaped(shape: TerrainShape, where := Vector3.ZERO, base := 0.0) -> HeightField:
	var field := HeightField.covering(Vector2(100, 100), 1.0)
	field.heights.fill(base)
	shape.apply(field, Transform3D(Basis.IDENTITY, where))
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


func _test_drawn_road() -> void:
	var map := RoadMap.new()
	var terrain := Terrain.new()
	terrain.size = Vector2(80, 80)
	var plateau := TerrainShape.new()
	plateau.kind = TerrainShape.Kind.PLATEAU
	plateau.height = 2.0
	plateau.radius = 200.0
	map.add_child(terrain)
	terrain.add_child(plateau)
	var road := MeshInstance3D.new()
	var slab := BoxMesh.new()
	slab.size = Vector3(7, 0.02, 40)
	road.mesh = slab
	road.material_override = Terrain.ASPHALT
	road.position = Vector3(-10, 0.01, 0)
	map.add_child(road)
	var grass := MeshInstance3D.new()
	grass.mesh = slab
	grass.position = Vector3(20, 0.01, 0)
	map.add_child(grass)
	var top := 0.02 - Terrain.ROAD_SINK
	var middle := terrain.height_at(Vector3(-10, 0, 0))
	var edge := terrain.height_at(Vector3(-10 + 3.5 + Terrain.SHOULDER - 0.5, 0, 15))
	var past_end := terrain.height_at(Vector3(-10, 0, -20 - 3.5 - Terrain.SHOULDER - terrain.road_blend - 1.0))
	expect(is_equal_approx(middle, top) and absf(edge - top) < 0.01,
		"the land lies 5 cm under a road drawn by hand, out to its shoulder: %.3f, %.3f" % [middle, edge])
	expect(Terrain.is_drawn_road(road) and not Terrain.is_drawn_road(grass)
		and is_equal_approx(terrain.height_at(Vector3(20, 0, 0)), 2.0) and is_equal_approx(past_end, 2.0),
		"a mesh without the asphalt is not road, and the land is its own past the road's end")
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
	var edit := TerrainAuthoring.drape(map)
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
	var map: RoadMap = load(MapFiles.BASE).instantiate()
	var edit := TerrainAuthoring.add_terrain(map)
	edit.apply(map)
	var environment := map.get_node("Environment") as RoadEnvironment
	expect(Terrain.of(map) != null and not environment.ground
		and TerrainAuthoring.add_terrain(map).is_empty(),
		"adding terrain turns the flat ground off, and is done once")
	map.free()


func _test_handles() -> void:
	for kind: int in TerrainShape.Kind.values():
		var shape := _shape(kind, 4.0)
		var ground_height := 1.5
		var worst := 0.0
		for handle: Dictionary in shape.handles(ground_height):
			var back := shape.value_from(handle.name, handle.local, ground_height)
			worst = maxf(worst, absf(back - shape.handle_value(handle.name)))
		expect(worst < 0.0001, "%s: each handle gives back the value it shows: %.5f off"
			% [TerrainShape.Kind.keys()[kind], worst])
		shape.free()
	var hill := _shape(TerrainShape.Kind.HILL, 4.0)
	var where: Vector3 = hill.handles()[0].local
	expect(is_equal_approx(hill.value_from(TerrainShape.RADIUS, where + Vector3(3, 0, 0)), 8.0)
		and hill.value_from(TerrainShape.HEIGHT, Vector3(0, -2, 0), 1.0) == 0.0,
		"a radius dragged 3 m out grows 3 m; a hill's height never goes below its land")
	hill.free()


func _test_outline() -> void:
	var ramp := _shape(TerrainShape.Kind.RAMP, 3.0)
	var land := func(p: Vector3) -> float: return 0.1 * p.x - 0.05 * p.z
	var worst := 0.0
	var points := 0
	for loop in TerrainShape.drape(ramp.outline_loops(), land, 0.0):
		for p in loop:
			worst = maxf(worst, absf(p.y - land.call(p)))
			points += 1
	expect(points > 40 and worst < 0.0001,
		"the outline lies on the land, %d points along it" % points)
	ramp.free()


## A terrain over a map, with a hill on it, in the tree; and the hill.
func _live_terrain(extent: float, where := Vector3.ZERO) -> Array:
	var map := RoadMap.new()
	var terrain := Terrain.new()
	terrain.size = Vector2(extent, extent)
	map.add_child(terrain)
	var hill := TerrainShape.new()
	hill.height = 6.0
	hill.radius = 8.0
	hill.falloff = 12.0
	hill.position = where
	map.add_child(hill)
	var plateau := TerrainShape.new()
	plateau.kind = TerrainShape.Kind.PLATEAU
	plateau.height = 2.0
	plateau.position = where + Vector3(15, 0, 4)
	map.add_child(plateau)
	root.add_child(map)
	return [map, terrain, hill]


func _test_partial_rebuild() -> void:
	var made := _live_terrain(200.0)
	var map: RoadMap = made[0]
	var terrain: Terrain = made[1]
	var hill: TerrainShape = made[2]
	await process_frame
	var was := terrain.shape_area(hill)
	hill.position = Vector3(20, 0, -10)
	hill.radius = 11.0
	var t := Time.get_ticks_usec()
	terrain.rebuild_area(was.merge(terrain.shape_area(hill)))
	var partial := (Time.get_ticks_usec() - t) / 1000.0
	var drawn := terrain.chunks_drawn
	var patched := terrain.field().heights.duplicate()
	t = Time.get_ticks_usec()
	terrain.rebuild()
	var whole := (Time.get_ticks_usec() - t) / 1000.0
	var full := terrain.field().heights
	var worst := 0.0
	for k in full.size():
		worst = maxf(worst, absf(full[k] - patched[k]))
	expect(worst < 0.0001, "built again only where the hill was and is, the land is the same as "
		+ "built whole: %.5f m off at worst" % worst)
	expect(drawn > 0 and drawn < terrain.chunks_drawn,
		"and it draws %d of the %d chunks again" % [drawn, terrain.chunks_drawn])
	if OS.has_environment("TESTS_BENCH"):
		print("terrain 200 m at 1 m: whole %.1f ms, a hill moved %.1f ms" % [whole, partial])
	map.queue_free()
	await process_frame


func _test_shape_edits() -> void:
	var made := _live_terrain(120.0)
	var map: RoadMap = made[0]
	var terrain: Terrain = made[1]
	var hill: TerrainShape = made[2]
	await process_frame
	var plateau := TerrainShape.new()
	plateau.kind = TerrainShape.Kind.PLATEAU
	plateau.position = Vector3(0, 9, 0)
	map.add_child(plateau)
	terrain.rebuild()
	var under := terrain.land_height_at(Vector3.ZERO, terrain.land(plateau))
	var with_it := terrain.land_height_at(Vector3.ZERO)
	TerrainAuthoring.snap_shape_base(map, plateau).apply(map)
	expect(is_equal_approx(plateau.position.y, under) and under > 1.0
		and absf(with_it - under) > 1.0,
		"standing a plateau on the land puts its base on the land under it, not on itself: "
		+ "%.2f m (%.2f with it)" % [plateau.position.y, with_it])
	TerrainAuthoring.set_shape(hill, TerrainShape.WIDTH, 7.0).apply(map)
	TerrainAuthoring.set_shape(hill, &"kind", TerrainShape.Kind.RAMP).apply(map)
	TerrainAuthoring.set_shape(hill, TerrainShape.FALLOFF, 3.5).apply(map)
	expect(hill.kind == TerrainShape.Kind.RAMP and hill.size.x == 7.0 and hill.falloff == 3.5,
		"the dock's edits set the kind, a ramp's width and the falloff")
	expect(TerrainAuthoring.shape_fields(TerrainShape.Kind.RAMP).has(TerrainShape.LENGTH)
		and not TerrainAuthoring.shape_fields(TerrainShape.Kind.HILL).has(TerrainShape.LENGTH),
		"a ramp is sized by its length and width, the rest by their radius")
	map.queue_free()
	await process_frame
