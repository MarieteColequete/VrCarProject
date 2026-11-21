class_name MapCatalogue
extends RefCounted
## Every map in [constant ROOT], found by scanning its folders: a map is
## [code]res://maps/<name>/<name>.tscn[/code] with a [RoadMap] root, so adding a map is adding its
## folder, with no list to edit. The scan reads each map's title from the scene's state, without
## instancing it, and lists maps by folder name. It goes through [ResourceLoader] rather than
## [DirAccess], so it also finds maps in an exported build, where scenes are remapped.

const ROOT := "res://maps/"


## One map the scan found.
class Entry:
	extends RefCounted
	## The map's id, or its folder's name when the map sets none.
	var id: StringName
	var title: String
	var path: String

	func load_scene() -> PackedScene:
		return load(path) as PackedScene


## The maps under [param root], sorted by folder name.
static func scan(root := ROOT) -> Array[Entry]:
	var found: Array[Entry] = []
	var folders := Array(ResourceLoader.list_directory(root)).filter(
		func(name: String) -> bool: return name.ends_with("/"))
	folders.sort()
	for folder: String in folders:
		var name := folder.trim_suffix("/")
		var path := root.path_join(name).path_join(name + ".tscn")
		if not ResourceLoader.exists(path, "PackedScene"):
			push_warning("The map folder %s has no %s.tscn; it is left out" % [folder, name])
			continue
		var entry := Entry.new()
		entry.path = path
		entry.id = StringName(name)
		entry.title = name.capitalize()
		var state := (load(path) as PackedScene).get_state()
		for i in state.get_node_property_count(0):
			match state.get_node_property_name(0, i):
				&"id":
					var value: StringName = state.get_node_property_value(0, i)
					if not value.is_empty():
						entry.id = value
				&"title":
					var value: String = state.get_node_property_value(0, i)
					if not value.is_empty():
						entry.title = value
		found.append(entry)
	return found


## The map with [param id], or null.
static func find(id: StringName, root := ROOT) -> Entry:
	for entry in scan(root):
		if entry.id == id:
			return entry
	return null
