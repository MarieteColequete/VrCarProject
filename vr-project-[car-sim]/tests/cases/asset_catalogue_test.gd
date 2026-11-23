extends TestCase
## The asset packs: the catalogue finds every model with its category, a folder without a pack
## file is listed under Other at the models' own size, and a map asset shows its model, solid or
## looks only, bakes into an obstacle, and steps to the next model of its category. Packs are told
## apart by their short names.

const PLAIN := "res://tests/fixtures/assets/"


func run() -> void:
	_test_scan()
	_test_plain_folder()
	_test_packs()
	_test_map_asset()
	_test_next_look()
	await _test_bake()


func _test_scan() -> void:
	var entries := AssetCatalogue.scan()
	var other := entries.filter(func(e: AssetCatalogue.Entry) -> bool:
		return e.category == AssetPack.OTHER)
	var categories := AssetCatalogue.categories(entries)
	expect(entries.size() == 366 and other.is_empty(),
		"the six kits' 366 models are found, each in a category %s"
			% [other.map(func(e: AssetCatalogue.Entry) -> String: return e.model_name)])
	expect(categories[0] == "Cars" and categories.has("Houses") and categories.has("Trees")
		and categories.has("Paths and driveways"), "categories are listed in their order")
	var sedan := entries.filter(func(e: AssetCatalogue.Entry) -> bool:
		return e.model_name == "sedan")
	expect(sedan.size() == 1 and sedan[0].category == "Cars" and sedan[0].pack.title == "Car Kit"
		and sedan[0].preview.ends_with("previews/sedan.png") and sedan[0].label == "Sedan",
		"a model knows its category, pack, preview, and label")
	expect(MapAsset.label_of("building-type-a") == "Building type a", "file names read as labels")


func _test_packs() -> void:
	var entries := AssetCatalogue.scan()
	var tags := AssetCatalogue.packs(entries).map(func(p: AssetPack) -> String: return p.short_title())
	expect(tags == ["Car Kit", "Suburban", "Roads", "Commercial", "Industrial", "Trains"],
		"the packs are listed in their categories' order, by short name: %s" % [tags])
	var labels := {}
	for entry in entries:
		if entry.model_name == "building-a":
			labels[entry.pack.short_title()] = entry.label
	expect(labels == {Commercial = "Building a · Commercial", Industrial = "Building a · Industrial"},
		"a model name two packs use is labelled with its pack: %s" % [labels])
	var house := catalogue_entry("building-type-a")
	expect(house.label == "Building type a", "a name only one pack uses keeps its plain label")
	var shop := catalogue_entry("building-skyscraper-a")
	var awning := catalogue_entry("detail-awning")
	var container := catalogue_entry("shipping-container-a")
	expect(shop.category == "Skyscrapers" and shop.body() == BodyType.of(&"obstacle")
		and awning.body() == null and container.category == "Shipping containers",
		"the commercial and industrial models have their categories and body types")
	var size := KitModels.size_of(container.path)
	expect(size.x > 2.3 and size.x < 2.8 and size.z > 5.5 and size.z < 6.2,
		"a shipping container is about the size of a real 20 foot one: %s" % size)

	var tram := catalogue_entry("train-tram-modern")
	var rail := catalogue_entry("railroad-straight")
	var wagon := KitModels.size_of(catalogue_entry("train-carriage-box").path)
	expect(tram.category == "Trams" and tram.body() == BodyType.of(&"vehicle") and rail.body() == null
		and wagon.x > 2.8 and wagon.x < 3.2,
		"trains are vehicles about 3 m wide, and the railway track is looks only")

	var bare := AssetPack.new()
	bare.title = "City Kit (Harbour)"
	var named := AssetPack.new()
	named.title = "Harbour"
	expect(bare.short_title() == "Harbour" and named.short_title() == "Harbour",
		"a pack's short name is its title's part in brackets, or its title")


func _test_plain_folder() -> void:
	var entries := AssetCatalogue.scan(PLAIN)
	expect(entries.size() == 1 and entries[0].category == AssetPack.OTHER
		and entries[0].pack.title == "Plain" and entries[0].body() == BodyType.of(&"obstacle"),
		"a folder of models without a pack file is listed under Other")
	var size := KitModels.size_of(entries[0].path) if not entries.is_empty() else Vector3.ZERO
	expect(size.x > 0.6 and size.x < 0.8, "its models keep their own size")


func _test_map_asset() -> void:
	var car := AssetCatalogue.make(catalogue_entry("taxi"))
	root.add_child(car)
	expect(car.bodies().size() == 1 and car.size().is_equal_approx(Vector3(1.8, 1.5, 4.3)),
		"a car from the pane is solid and fitted to a car's size")
	car.free()
	var tree_asset := AssetCatalogue.make(catalogue_entry("tree-large"))
	root.add_child(tree_asset)
	var box: Vector3 = (tree_asset.bodies()[0].get_child(0) as CollisionShape3D).shape.size
	expect(is_equal_approx(box.y, tree_asset.size().y) and box.x < tree_asset.size().x,
		"a tree is solid at its trunk only")
	tree_asset.free()
	var path_asset := AssetCatalogue.make(catalogue_entry("path-long"))
	root.add_child(path_asset)
	expect(path_asset.bodies().is_empty() and path_asset.get_child_count(true) == 1,
		"a path is looks only")
	expect(path_asset.get_child_count() == 0, "a map asset saves no children")
	path_asset.free()
	var missing := MapAsset.new()
	root.add_child(missing)
	expect(not missing._get_configuration_warnings().is_empty(),
		"a map asset with no model warns")
	missing.free()


func _test_next_look() -> void:
	var house := AssetCatalogue.make(catalogue_entry("building-type-a"))
	root.add_child(house)
	AssetTools.next_look([house]).apply(house)
	expect(house.model.ends_with("building-type-b.glb"),
		"next look steps to the category's next model")
	var last := AssetCatalogue.make(catalogue_entry("building-type-u"))
	root.add_child(last)
	AssetTools.next_look([last]).apply(last)
	expect(last.model.ends_with("building-type-a.glb"), "and wraps round")
	house.free()
	last.free()


func _test_bake() -> void:
	var road_map := RoadMap.new()
	road_map.name = "Assets"
	var spawn := MapSpawn.new()
	var van := AssetCatalogue.make(catalogue_entry("van"))
	van.position = Vector3(5, 0, -10)
	var path_asset := AssetCatalogue.make(catalogue_entry("path-short"))
	for node: Node in [spawn, van, path_asset]:
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
