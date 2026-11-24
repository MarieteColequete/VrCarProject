@tool
class_name AssetTools
extends RefCounted
## The map's models: a solid body for a mesh, the next look of a prop, scenery, or map asset, and
## loose models made into map assets.

## A static body of the obstacle [BodyType] with a box around [param node]'s meshes, local to it; null
## when it has no meshes.
static func obstacle_body(node: Node3D) -> StaticBody3D:
	var bounds := _bounds(node, Transform3D.IDENTITY)
	if bounds == null:
		return null
	var box: AABB = bounds
	var body := StaticBody3D.new()
	body.name = "Obstacle"
	BodyType.of(&"obstacle").apply(body)
	var shape := CollisionShape3D.new()
	shape.name = "Shape"
	var size := BoxShape3D.new()
	size.size = box.size.max(Vector3.ONE * 0.05)
	shape.shape = size
	shape.position = box.get_center()
	body.add_child(shape)
	return body


static func _bounds(node: Node, to_root: Transform3D) -> Variant:
	var out: Variant = null
	var here := to_root
	if node is VisualInstance3D:
		var box: AABB = here * (node as VisualInstance3D).get_aabb()
		out = box
	for child in node.get_children(true):
		var child_transform := here * (child as Node3D).transform if child is Node3D else here
		var inner: Variant = _bounds(child, child_transform)
		if inner != null:
			out = inner if out == null else (out as AABB).merge(inner)
	return out


## Every prop, scenery, and map asset of [param nodes] with its next look: the next variant of a
## prop with several, the next kind of scenery, the next model of a map asset's category.
static func next_look(nodes: Array) -> MapKitTools.Edit:
	var edit := MapKitTools.Edit.new()
	var entries: Array[AssetCatalogue.Entry] = []
	for node: Node in nodes:
		if node is Prop and (node as Prop).preset in [Prop.Preset.PARKED_CAR, Prop.Preset.VAN,
				Prop.Preset.BUILDING]:
			edit.set_value(node, &"variant", (node as Prop).variant + 1)
		elif node is Scenery:
			edit.set_value(node, &"kind",
				posmod((node as Scenery).kind + 1, Scenery.Kind.size()))
		elif node is MapAsset:
			if entries.is_empty():
				entries = AssetCatalogue.scan()
			var next := next_asset((node as MapAsset).model, entries)
			if next:
				set_model(edit, node as MapAsset, next)
	return edit


## Gives [param asset] the model of [param entry], set up as its category says, in [param edit].
static func set_model(edit: MapKitTools.Edit, asset: MapAsset, entry: AssetCatalogue.Entry) -> void:
	var template := AssetCatalogue.make(entry)
	for property in MapAsset.SETTINGS:
		edit.set_value(asset, property, template.get(property))
	template.free()


## The model after [param model_path] in its category and pack of [param entries] (the
## [AssetCatalogue]'s scan), wrapping round; null when it is not listed.
static func next_asset(model_path: String,
		entries: Array[AssetCatalogue.Entry]) -> AssetCatalogue.Entry:
	var at := -1
	for i in entries.size():
		if entries[i].path == model_path:
			at = i
	if at < 0:
		return null
	var same := entries.filter(func(e: AssetCatalogue.Entry) -> bool:
		return e.category == entries[at].category and e.pack == entries[at].pack)
	return same[(same.find(entries[at]) + 1) % same.size()]


## Gives the meshes among [param nodes] the asphalt material, so they are road.
static func set_as_road(nodes: Array) -> MapKitTools.Edit:
	var edit := MapKitTools.Edit.new()
	for node in nodes:
		if node is GeometryInstance3D:
			edit.set_value(node, &"material_override", MapKitTools.ASPHALT)
	return edit


## Gives each of [param nodes] without one a solid body on the obstacle layer
## ([method obstacle_body]).
static func set_as_obstacle(nodes: Array) -> MapKitTools.Edit:
	var edit := MapKitTools.Edit.new()
	for node in nodes:
		if node is Node3D and not node is StaticBody3D and not node.has_node("Obstacle"):
			var body := obstacle_body(node)
			if body:
				edit.add(node, body)
	return edit


## Whether [param node] is a loose model: a [code].glb[/code] under [constant AssetCatalogue.ROOT]
## dragged from the FileSystem dock straight onto the map. Nothing collides with it, road users do
## not see it, and the Map Kit cannot step through its looks.
static func is_loose_model(node: Node) -> bool:
	return node is Node3D and node.scene_file_path.begins_with(AssetCatalogue.ROOT) \
		and node.scene_file_path.get_extension() == "glb"


## The loose models among [param nodes] and their descendants, a model's own parts left out.
static func loose_models(nodes: Array) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for node: Node in nodes:
		_find_loose(node, out)
	return out


static func _find_loose(node: Node, out: Array[Node3D]) -> void:
	if is_loose_model(node):
		if not out.has(node):
			out.append(node)
		return
	for child in node.get_children():
		_find_loose(child, out)


## A [MapAsset] in place of the loose [param model], looking as it does: the same name, place,
## turn, and size, and the body its category in [param entries] (the [AssetCatalogue]'s scan)
## gives, or an obstacle's for a model in none. A model stretched unevenly keeps its stretch as the
## asset's [member MapAsset.fit].
static func as_map_asset(model: Node3D, entries: Array[AssetCatalogue.Entry]) -> MapAsset:
	var path := model.scene_file_path
	var asset: MapAsset = null
	for entry in entries:
		if entry.path == path:
			asset = AssetCatalogue.make(entry)
			break
	if asset == null:
		asset = MapAsset.new()
		asset.model = path
	asset.name = model.name
	# The model's file drawn at the model's transform, as the asset draws its mesh: the asset's
	# transform times its scale times the fitting is the model's transform.
	var drawn := model.transform * KitModels.fitting(path).affine_inverse()
	var stretch := drawn.basis.get_scale()
	asset.transform = Transform3D(drawn.basis.orthonormalized(), drawn.origin)
	if is_equal_approx(stretch.x, stretch.y) and is_equal_approx(stretch.y, stretch.z):
		asset.fit = Vector3.ZERO
		asset.extra_scale = stretch.x
	else:
		asset.fit = stretch * KitModels.size_of(path)
		asset.extra_scale = 1.0
	return asset


## Each loose model among [param nodes] and their descendants made into a [MapAsset] looking as it
## does ([method as_map_asset]).
static func make_map_assets(nodes: Array) -> MapKitTools.Edit:
	var edit := MapKitTools.Edit.new()
	var models := loose_models(nodes)
	if models.is_empty():
		return edit
	var entries := AssetCatalogue.scan()
	for model in models:
		edit.remove(model)
		edit.add(model.get_parent(), as_map_asset(model, entries))
	return edit
