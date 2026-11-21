extends TestCase
## The asset packs: the catalogue finds every model with its category, a folder without a pack
## file is listed under Other at the models' own size, and a map asset shows its model, solid or
## looks only, bakes into an obstacle, and steps to the next model of its category.

const PLAIN := "res://tests/fixtures/assets/"


func run() -> void:
	_test_scan()
	_test_plain_folder()
	_test_map_asset()
	_test_next_look()
	await _test_bake()


func _test_scan() -> void:
	var entries := AssetCatalogue.scan()
	var other := entries.filter(func(e: AssetCatalogue.Entry) -> bool:
		return e.category == AssetPack.OTHER)
	var categories := AssetCatalogue.categories(entries)
	expect(entries.size() == 185 and other.is_empty(),
		"the three kits' 185 models are found, each in a category %s"
			% [other.map(func(e: AssetCatalogue.Entry) -> String: return e.model_name)])
	expect(categories[0] == "Cars" and categories.has("Houses") and categories.has("Trees")
		and categories.has("Paths and driveways"), "categories are listed in their order")
	var sedan := entries.filter(func(e: AssetCatalogue.Entry) -> bool:
		return e.model_name == "sedan")
	expect(sedan.size() == 1 and sedan[0].category == "Cars" and sedan[0].pack.title == "Car Kit"
		and sedan[0].preview.ends_with("previews/sedan.png") and sedan[0].label == "Sedan",
		"a model knows its category, pack, preview, and label")
	expect(MapAsset.label_of("building-type-a") == "Building type a", "file names read as labels")


func _test_plain_folder() -> void:
	var entries := AssetCatalogue.scan(PLAIN)
	expect(entries.size() == 1 and entries[0].category == AssetPack.OTHER
		and entries[0].pack.title == "Plain" and entries[0].body() == BodyType.of(&"obstacle"),
		"a folder of models without a pack file is listed under Other")
	var size := KitModels.size_of(entries[0].path) if not entries.is_empty() else Vector3.ZERO
	expect(size.x > 0.6 and size.x < 0.8, "its models keep their own size")


func _entry(model_name: String) -> AssetCatalogue.Entry:
	for entry in AssetCatalogue.scan():
		if entry.model_name == model_name:
			return entry
	return null


func _test_map_asset() -> void:
	var car := AssetCatalogue.make(_entry("taxi"))
	root.add_child(car)
	expect(car.bodies().size() == 1 and car.size().is_equal_approx(Vector3(1.8, 1.5, 4.3)),
		"a car from the pane is solid and fitted to a car's size")
	car.free()
	var tree := AssetCatalogue.make(_entry("tree-large"))
	root.add_child(tree)
	var box: Vector3 = (tree.bodies()[0].get_child(0) as CollisionShape3D).shape.size
	expect(is_equal_approx(box.y, tree.size().y) and box.x < tree.size().x,
		"a tree is solid at its trunk only")
	tree.free()
	var path := AssetCatalogue.make(_entry("path-long"))
	root.add_child(path)
	expect(path.bodies().is_empty() and path.get_child_count(true) == 1,
		"a path is looks only")
	expect(path.get_child_count() == 0, "a map asset saves no children")
	path.free()
	var missing := MapAsset.new()
	root.add_child(missing)
	expect(not missing._get_configuration_warnings().is_empty(),
		"a map asset with no model warns")
	missing.free()


func _test_next_look() -> void:
	var house := AssetCatalogue.make(_entry("building-type-a"))
	root.add_child(house)
	MapKitTools.next_look([house]).apply(house)
	expect(house.model.ends_with("building-type-b.glb"),
		"next look steps to the category's next model")
	var last := AssetCatalogue.make(_entry("building-type-u"))
	root.add_child(last)
	MapKitTools.next_look([last]).apply(last)
	expect(last.model.ends_with("building-type-a.glb"), "and wraps round")
	house.free()
	last.free()


func _test_bake() -> void:
	var road_map := RoadMap.new()
	road_map.name = "Assets"
	var spawn := MapSpawn.new()
	var van := AssetCatalogue.make(_entry("van"))
	van.position = Vector3(5, 0, -10)
	var path := AssetCatalogue.make(_entry("path-short"))
	for node: Node in [spawn, van, path]:
		road_map.add_child(node)
		node.owner = road_map
	var packed := PackedScene.new()
	packed.pack(road_map)
	road_map.free()
	var runner: ExamRunner = RUNNER.instantiate()
	runner.print_results = false
	runner.scenario_scene = null
	root.add_child(runner)
	runner.load_map(packed)
	await process_frame
	var obstacles := runner.world().store(Schema.OBSTACLE)
	expect(obstacles.size() == 1, "a solid map asset bakes into one obstacle, scenery none")
	runner.queue_free()
	await process_frame
