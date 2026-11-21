extends TestCase
## The Kenney models: every model builds into one mesh at the kit's scale, the props, scenery, and
## parked cars show them with boxes that fit, and road users are drawn as cars.


func run() -> void:
	_test_meshes()
	_test_props()
	_test_scenery()
	_test_box_body()
	await _test_road_users()


func _test_meshes() -> void:
	var broken := PackedStringArray()
	for kit in [KitModels.CAR_KIT, KitModels.SUBURBAN]:
		for file in DirAccess.get_files_at(kit):
			if not file.ends_with(".glb"):
				continue
			var mesh := KitModels.mesh(kit + file)
			if mesh == null or mesh.get_surface_count() != 1 or mesh.get_aabb().size.y <= 0.0 \
					or absf(mesh.get_aabb().position.y) > 0.001:
				broken.append(file)
	expect(broken.is_empty(), "every model builds as one mesh standing on its origin %s" % [broken])
	var sedan := KitModels.mesh(KitModels.car(0))
	expect(sedan.get_aabb().size.z > 4.0 and sedan.get_aabb().size.z < 4.6,
		"a sedan is a car's length")
	var unit := KitModels.unit_mesh(KitModels.car(0))
	expect(unit.get_aabb().size.is_equal_approx(Vector3.ONE), "a unit mesh fills a one metre cube")
	expect(KitModels.mesh("res://assets/kenney/no_such.glb") == null,
		"a missing model builds nothing")
	var previews := PackedStringArray()
	for piece in MapKitTools.pieces():
		if not ResourceLoader.exists(piece.icon):
			previews.append(piece.label)
	expect(previews.is_empty(), "every palette piece has an icon %s" % [previews])


func _test_props() -> void:
	var problems := PackedStringArray()
	for preset in Prop.Preset.values():
		var prop := Prop.new()
		prop.preset = preset
		root.add_child(prop)
		var body: StaticBody3D = prop.bodies()[0] if not prop.bodies().is_empty() else null
		var shape := body.get_child(0) as CollisionShape3D if body else null
		var has_model := not prop.model().is_empty()
		var shows := body != null and body.get_children().any(func(c: Node) -> bool:
			return c is MeshInstance3D and (c as MeshInstance3D).mesh != null)
		if shape == null or shape.shape.size.x < 0.1 or not shows:
			problems.append(Prop.Preset.keys()[preset])
		if has_model != (preset not in [Prop.Preset.BARRIER, Prop.Preset.BOLLARD]):
			problems.append("%s model" % Prop.Preset.keys()[preset])
		prop.free()
	expect(problems.is_empty(), "every prop preset shows a model or shape in a solid box %s"
		% [problems])
	var car := Prop.new()
	car.variant = 3
	root.add_child(car)
	expect(car.model().ends_with("taxi.glb") and car.box_size().is_equal_approx(Prop.FITS[
		Prop.Preset.PARKED_CAR]),
		"a parked car's variant picks the kit's car, fitted to a car's size")
	car.free()
	var house := Prop.new()
	house.preset = Prop.Preset.BUILDING
	house.building_size = Vector3(12, 8, 9)
	root.add_child(house)
	var size := house.box_size()
	expect(is_equal_approx(size.x, 12.0) and is_equal_approx(size.z, 9.0) and size.y > 3.0,
		"a building's house is stretched to its width and depth")
	house.free()


func _test_scenery() -> void:
	var piece := Scenery.new()
	piece.kind = Scenery.Kind.DRIVEWAY_LONG
	root.add_child(piece)
	var part := piece.get_child(0, true) as MeshInstance3D
	expect(part != null and part.mesh != null and piece.get_child_count() == 0
		and not piece.find_children("*", "CollisionObject3D", true, false).size(),
		"scenery shows its model, saves no children, and has nothing to collide with")
	piece.kind = Scenery.Kind.PATH_SHORT
	expect(part.mesh == KitModels.mesh(KitModels.suburban("path-short")),
		"changing the kind shows its model")
	piece.free()


func _test_box_body() -> void:
	var body := StaticBody3D.new()
	BoxBody.build(body, Vector3(1.8, 1.4, 4.2), Color.RED, KitModels.car(1))
	var part := body.get_child(1) as MeshInstance3D
	var box := part.mesh.get_aabb() if part else AABB()
	expect(part != null and (box.size * part.scale).is_equal_approx(Vector3(1.8, 1.4, 4.2)),
		"a box body shows its model fitted to the box")
	body.free()


func _test_road_users() -> void:
	var runner: ExamRunner = RUNNER.instantiate()
	runner.print_results = false
	runner.scenario_scene = null
	root.add_child(runner)
	runner.load_map(load("res://maps/sample_town/sample_town.tscn"))
	await frames(240)
	var counts: Dictionary = runner._traffic_view.counts() if runner._traffic_view else {}
	var cars := counts.keys().filter(func(k: String) -> bool:
		return k.begins_with(KitModels.CAR_KIT))
	var drawn: int = counts.values().reduce(func(a: int, b: int) -> int: return a + b, 0)
	expect(not cars.is_empty() and drawn == runner.world().store(Schema.AGENT).size(),
		"road users are drawn as the kit's cars, each once %s" % [counts])
	runner.queue_free()
	await process_frame
