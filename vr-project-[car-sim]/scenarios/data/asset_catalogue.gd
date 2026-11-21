@tool
class_name AssetCatalogue
extends RefCounted
## Every model under [constant ROOT], found by scanning its folders: each folder holding
## [code].glb[/code] models is an [AssetPack], and each model is listed under the first of the
## pack's [AssetCategory]s it matches, or under [constant AssetPack.OTHER]. Adding models is
## adding a folder, with no list to edit. The Asset Library pane of the Map Kit lists them.

const ROOT := "res://assets/"


## One model the scan found.
class Entry:
	extends RefCounted
	## The model's [code].glb[/code].
	var path: String
	## The model's name, such as [code]sedan[/code].
	var model_name: String
	## The name to show, such as "Sedan".
	var label: String
	var pack: AssetPack
	## The category's title.
	var category: String
	## The category it is listed under; null for [constant AssetPack.OTHER].
	var rules: AssetCategory
	## The pack's preview image of it; empty when the pack has none.
	var preview: String

	## What kind of solid it is; null for looks only. A model in no category is an obstacle.
	func body() -> BodyType:
		return rules.body if rules else BodyType.of(&"obstacle")

	## The kind of solid as a name to show.
	func body_title() -> String:
		var kind := body()
		return kind.title if kind else "Looks only"

	func order() -> int:
		return rules.order if rules else 1000


## Every model under [param root], by category order, category, and name.
static func scan(root := ROOT) -> Array[Entry]:
	var found: Array[Entry] = []
	_scan_folder(root.trim_suffix("/"), found)
	found.sort_custom(func(a: Entry, b: Entry) -> bool:
		if a.order() != b.order():
			return a.order() < b.order()
		if a.category != b.category:
			return a.category < b.category
		return a.model_name < b.model_name)
	return found


## The categories' titles among [param entries], in their order, each once.
static func categories(entries: Array[Entry]) -> PackedStringArray:
	var out := PackedStringArray()
	for entry in entries:
		if not out.has(entry.category):
			out.append(entry.category)
	return out


## A [MapAsset] showing [param entry], set up as its category says.
static func make(entry: Entry) -> MapAsset:
	var asset := MapAsset.new()
	asset.name = entry.model_name.to_pascal_case()
	asset.model = entry.path
	var rules := entry.rules
	asset.body_type = entry.body()
	if rules:
		asset.mesh_collider = rules.collider == AssetCategory.Collider.MESH
		asset.fit = rules.fit
		asset.extra_scale = rules.extra_scale
		asset.solid_part = rules.solid_part
	return asset


static func _scan_folder(folder: String, found: Array[Entry]) -> void:
	var files := DirAccess.get_files_at(folder)
	var models := Array(files).filter(func(f: String) -> bool: return f.get_extension() == "glb")
	if not models.is_empty():
		var pack := AssetPack.of_folder(folder)
		for file: String in models:
			var entry := Entry.new()
			entry.path = folder.path_join(file)
			entry.model_name = file.get_basename()
			entry.label = MapAsset.label_of(entry.model_name)
			entry.pack = pack
			entry.rules = pack.category_of(entry.model_name)
			entry.category = entry.rules.title if entry.rules else AssetPack.OTHER
			var preview := folder.path_join("previews").path_join(entry.model_name + ".png")
			entry.preview = preview if ResourceLoader.exists(preview) else ""
			found.append(entry)
	for sub in DirAccess.get_directories_at(folder):
		if not sub.begins_with(".") and sub != "previews":
			_scan_folder(folder.path_join(sub), found)
