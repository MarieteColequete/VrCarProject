extends TestCase
## The Asset Library apart from its pane: what it shows for a source, category, chips, and
## search; favourites, recent models, and turns kept between sessions; a model's size without a
## node; the placer's ghost and placement; stepping and replacing a model keeping its body; and the
## thumbnails' cache names and framing.


func run() -> void:
	var model := AssetLibraryModel.new()
	model.set_entries(AssetCatalogue.scan())
	_test_sources(model)
	_test_search(model)
	_test_kept(model)
	_test_sizes()
	_test_ghost()
	_test_settings_kept()
	_test_placement()
	_test_thumbnails()


func _test_sources(model: AssetLibraryModel) -> void:
	expect(model.shown().size() == model.entries.size(), "every pack shows every model")
	model.source = "Train Kit"
	var trains := model.shown()
	expect(trains.size() == 103 and trains.all(func(e: AssetCatalogue.Entry) -> bool:
		return e.pack.short_title() == "Trains"), "a pack shows its own models")
	var categories := model.categories()
	expect(categories[0] == ["Locomotives", 11] and categories.size() == 6,
		"a pack lists its categories in order with counts: %s" % [categories])
	model.category = "Trams"
	expect(model.shown().size() == 3, "a category narrows to its models")
	model.category = AssetLibraryModel.ALL
	model.kinds = PackedStringArray(["looks_only"])
	expect(model.shown().all(func(e: AssetCatalogue.Entry) -> bool: return e.body() == null)
		and model.shown().size() == 62, "the looks only chip shows the couplers and track")
	model.kinds = PackedStringArray(["vehicle", "looks_only"])
	expect(model.shown().size() == 103, "chips add together")
	model.clear_filters()
	expect(not model.filtered() and model.shown().size() == 103, "clearing the filters")

	model.source = AssetLibraryModel.FAVOURITES
	expect(model.shown().is_empty(), "no favourites at first")
	var tram := "res://assets/kenney/train_kit/train-tram-modern.glb"
	expect(model.toggle_favourite(tram) and model.shown().size() == 1,
		"a marked model shows among the favourites")
	expect(not model.toggle_favourite(tram) and model.shown().is_empty(), "and unmarked, leaves")

	model.source = AssetLibraryModel.RECENT
	var paths := model.entries.map(func(e: AssetCatalogue.Entry) -> String: return e.path)
	for i in 25:
		model.push_recent(paths[i])
	model.push_recent(paths[3])
	var recent := model.shown()
	expect(recent.size() == AssetLibraryModel.RECENT_MAX and recent[0].path == paths[3]
		and recent[1].path == paths[24], "recent keeps the last 20 placed, newest first, once each")
	model.source = AssetLibraryModel.ALL_PACKS


func _test_search(model: AssetLibraryModel) -> void:
	model.query = "pack:trains body:vehicle tram"
	var found := model.shown()
	expect(found.size() == 3 and found.all(func(e: AssetCatalogue.Entry) -> bool:
		return e.category == "Trams"), "pack and body words narrow a search: %d" % found.size())
	model.query = "cat:houses type-a"
	found = model.shown()
	expect(found.size() == 1 and found[0].model_name == "building-type-a",
		"cat words and plain words together")
	model.query = "Building A"
	expect(model.shown().size() >= 3, "plain words match labels, ignoring case")
	model.query = "pack:"
	expect(model.shown().size() == model.entries.size(), "an empty field word matches all")
	model.query = "nothing-like-this"
	expect(model.shown().is_empty() and model.filtered(), "a search matching nothing is empty")
	model.query = ""


func _test_kept(model: AssetLibraryModel) -> void:
	model.source = "City Kit (Commercial)"
	model.category = "Awnings"
	model.query = "wide"
	model.kinds = PackedStringArray(["looks_only"])
	model.view = AssetLibraryModel.LIST
	model.thumb_size = 999
	model.toggle_favourite("res://assets/kenney/car_kit/sedan.glb")
	model.set_turn("res://assets/kenney/car_kit/sedan.glb", PI / 2.0)
	var other := AssetLibraryModel.new()
	other.from_dict(model.to_dict())
	expect(other.source == model.source and other.category == "Awnings" and other.query == "wide"
		and other.kinds == model.kinds and other.view == AssetLibraryModel.LIST
		and other.favourites == model.favourites and other.recent == model.recent
		and is_equal_approx(other.turn_of("res://assets/kenney/car_kit/sedan.glb"), PI / 2.0),
		"the pane's state comes back as it was saved")
	expect(other.thumb_size == AssetLibraryModel.THUMB_MAX, "a thumbnail size out of range is held in")
	other.from_dict({view = "nonsense", turns = "nonsense"})
	expect(other.view == AssetLibraryModel.GRID and other.turns.is_empty(),
		"saved values of the wrong kind are ignored")
	model.set_turn("res://assets/kenney/car_kit/sedan.glb", 0.0)
	expect(model.turns.is_empty(), "a straight turn is not kept")


func _test_sizes() -> void:
	for model_name in ["building-type-a", "tree-large", "sedan", "train-tram-modern"]:
		var entry := _entry(model_name)
		var asset := AssetCatalogue.make(entry)
		expect(AssetCatalogue.shown_size(entry).is_equal_approx(asset.size()),
			"%s's size is known without making it" % model_name)
		asset.free()
	var sedan := _entry("sedan")
	expect(KitModels.triangles(sedan.path) > 100, "a model's triangles are counted")


func _test_ghost() -> void:
	var ghost := AssetCatalogue.make(_entry("building-type-a"))
	ghost.preview = true
	root.add_child(ghost)
	var part: MeshInstance3D = null
	for child in ghost.get_children(true):
		if child is MeshInstance3D:
			part = child
	expect(ghost.bodies().is_empty() and part != null
		and is_equal_approx(part.transparency, MapAsset.PREVIEW_TRANSPARENCY),
		"a ghost model is see-through and has no body")
	ghost.free()


## Stepping to the next look and replacing a model set every setting of its category, the body
## among them.
func _test_settings_kept() -> void:
	var tile := AssetCatalogue.make(_entry("road-straight"))
	root.add_child(tile)
	AssetTools.next_look([tile]).apply(tile)
	expect(tile.body_type == BodyType.of(&"pavement") and tile.mesh_collider
		and not tile.model.ends_with("road-straight.glb"),
		"a road tile's next look keeps its pavement body and surface collider")
	var edit := MapKitTools.Edit.new()
	AssetTools.set_model(edit, tile, _entry("detail-awning"))
	edit.apply(tile)
	expect(tile.body_type == null and not tile.mesh_collider
		and tile.model.ends_with("detail-awning.glb"),
		"replacing it with an awning makes it looks only, as awnings are")
	tile.free()


func _test_placement() -> void:
	var where := MapKitPlacer.placement(Vector3(1.26, 0.15, -3.74), 0.5, PI / 2.0, 0.0)
	expect(where.origin.is_equal_approx(Vector3(1.5, 0.15, -3.5))
		and where.basis.is_equal_approx(Basis(Vector3.UP, PI / 2.0)),
		"a piece snaps across to the grid, stands on the surface's height, and turns")
	var raised := MapKitPlacer.placement(Vector3(0, 2.0, 0), 0.0, 0.0, 0.5)
	expect(is_equal_approx(raised.origin.y, 2.5), "and keeps its own height above the surface")


func _test_thumbnails() -> void:
	var file_path := "res://assets/kenney/car_kit/sedan.glb"
	var name := AssetThumbnails.cache_name(file_path, 100, 1.7)
	expect(name != AssetThumbnails.cache_name(file_path, 101, 1.7)
		and name != AssetThumbnails.cache_name(file_path, 100, 2.0) and name.ends_with(".png"),
		"a thumbnail is rendered again when its model or its pack's scale changes")
	var camera := AssetThumbnails.camera_transform()
	var to_centre := (Vector3(0, 0.5, 0) - camera.origin).normalized()
	expect(to_centre.dot(-camera.basis.z) > 0.999 and camera.origin.y > 0.5
		and camera.origin.x > 0.0, "the thumbnail camera looks down at the model from the side")
	var fitted := AssetThumbnails.fit_transform(AABB(Vector3(-1, 0, -4), Vector3(2, 1.5, 8)))
	var box: AABB = fitted * AABB(Vector3(-1, 0, -4), Vector3(2, 1.5, 8))
	expect(is_equal_approx(box.size.z, 1.0) and is_equal_approx(box.size.x, 0.25)
		and is_zero_approx(box.position.y), "a long model fits the frame keeping its proportions")


func _entry(model_name: String) -> AssetCatalogue.Entry:
	for entry in AssetCatalogue.scan():
		if entry.model_name == model_name:
			return entry
	return null
