@tool
class_name MapFiles
extends RefCounted
## A map's files: creating a map from the base scene, renaming, duplicating and deleting one, and
## the scenarios that use it, whose paths a rename rewrites. Each returns an error, or an empty
## string, rather than failing.

const BASE := "res://scenarios/kit/map_base.tscn"
## Where the scenarios that may use a map live.
const USERS_ROOT := "res://scenarios/"


## Whether [param map_name] can name a map's folder and scene: lower case letters, digits, and
## underscores, starting with a letter.
static func is_map_name(map_name: String) -> bool:
	var pattern := RegEx.create_from_string("^[a-z][a-z0-9_]*$")
	return pattern.search(map_name) != null


## The scene of the map [param map_name] under [param root].
static func map_path(map_name: String, root := MapCatalogue.ROOT) -> String:
	return root.path_join(map_name).path_join(map_name + ".tscn")


## Creates [code]<root>/<map_name>/<map_name>.tscn[/code], a new inherited scene of the map base
## with its id and title set, and returns its path; empty when the name is not valid or the map
## exists.
static func create_map(map_name: String, title: String, root := MapCatalogue.ROOT) -> String:
	var path := map_path(map_name, root)
	if not is_map_name(map_name) or ResourceLoader.exists(path):
		return ""
	if DirAccess.make_dir_recursive_absolute(path.get_base_dir()) != OK:
		return ""
	# Written as text: an inherited scene keeps only what differs from the base, and the engine
	# offers no call to pack a scene as inheriting another.
	var text := "[gd_scene format=3]\n\n" \
		+ "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"base\"]\n\n" % BASE \
		+ "[node name=\"%s\" instance=ExtResource(\"base\")]\n" % map_name.to_pascal_case() \
		+ "id = &%s\n" % var_to_str(map_name) \
		+ "title = %s\n" % var_to_str(title if not title.is_empty() else map_name.capitalize())
	return path if _write(path, text) else ""


## The scenes under [param users_root] that use the map at [param path]: the scenarios that
## instance it.
static func map_users(path: String, users_root := USERS_ROOT) -> PackedStringArray:
	var out := PackedStringArray()
	var quoted := "\"%s\"" % path
	for scene in _scenes(users_root):
		if FileAccess.get_file_as_string(scene).contains(quoted):
			out.append(scene)
	return out


## Renames the map [param old] to [param new]: its folder, its scene, its root's name and id, and
## the path in every scenario using it. Returns why it could not; empty when it did.
static func rename_map(old: String, new: String, root := MapCatalogue.ROOT,
		users_root := USERS_ROOT) -> String:
	var problem := _check_new_name(old, new, root)
	if not problem.is_empty():
		return problem
	var old_path := map_path(old, root)
	var users := map_users(old_path, users_root)
	var text := FileAccess.get_file_as_string(old_path)
	if DirAccess.rename_absolute(root.path_join(old), root.path_join(new)) != OK:
		return "Could not move the folder %s." % root.path_join(old)
	var moved := root.path_join(new).path_join(old + ".tscn")
	if DirAccess.rename_absolute(moved, map_path(new, root)) != OK:
		return "Could not rename %s." % moved
	text = _set_root_name(text, new.to_pascal_case())
	text = _set_root_field(text, "id", "&" + var_to_str(new))
	if not _write(map_path(new, root), text):
		return "Could not write %s." % map_path(new, root)
	for user in users:
		_write(user, FileAccess.get_file_as_string(user).replace(
			"\"%s\"" % old_path, "\"%s\"" % map_path(new, root)))
	return ""


## Copies the map [param old] as [param new], titled [param title]: a scene of its own, with a new
## uid. Returns why it could not; empty when it did.
static func duplicate_map(old: String, new: String, title: String,
		root := MapCatalogue.ROOT) -> String:
	var problem := _check_new_name(old, new, root)
	if not problem.is_empty():
		return problem
	var text := FileAccess.get_file_as_string(map_path(old, root))
	text = RegEx.create_from_string(" uid=\"uid://[^\"]*\"").sub(text, "", false)
	text = _set_root_name(text, new.to_pascal_case())
	text = _set_root_field(text, "id", "&" + var_to_str(new))
	text = _set_root_field(text, "title",
		var_to_str(title if not title.is_empty() else new.capitalize()))
	if DirAccess.make_dir_recursive_absolute(root.path_join(new)) != OK \
			or not _write(map_path(new, root), text):
		return "Could not write %s." % map_path(new, root)
	return ""


## Deletes the map [param map_name] with its folder, to the system's trash when
## [param to_trash]. A map a scenario uses is kept. Returns why it could not; empty when it did.
static func delete_map(map_name: String, root := MapCatalogue.ROOT, users_root := USERS_ROOT,
		to_trash := true) -> String:
	var path := map_path(map_name, root)
	if not FileAccess.file_exists(path):
		return "There is no map %s." % map_name
	var users := map_users(path, users_root)
	if not users.is_empty():
		return "%s is used by %s." % [map_name, ", ".join(users)]
	var folder := root.path_join(map_name)
	if to_trash:
		return "" if OS.move_to_trash(ProjectSettings.globalize_path(folder)) == OK \
			else "Could not move %s to the trash." % folder
	_remove_tree(folder)
	return "" if not DirAccess.dir_exists_absolute(folder) else "Could not delete %s." % folder


static func _check_new_name(old: String, new: String, root: String) -> String:
	if not FileAccess.file_exists(map_path(old, root)):
		return "There is no map %s." % old
	if not is_map_name(new):
		return "Name the map with lower case letters, digits, and underscores, starting with a " \
			+ "letter."
	if DirAccess.dir_exists_absolute(root.path_join(new)):
		return "A map %s exists already." % new
	return ""


## [param text], a scene, with its root node named [param root_name].
static func _set_root_name(text: String, root_name: String) -> String:
	var pattern := RegEx.create_from_string("(?m)^\\[node name=\"[^\"]*\"")
	return pattern.sub(text, "[node name=\"%s\"" % root_name, false)


## [param text], a scene, with the root node's [param key] set to [param value], written as it
## is in a scene file.
static func _set_root_field(text: String, key: String, value: String) -> String:
	var lines := text.split("\n")
	var root := -1
	for i in lines.size():
		if lines[i].begins_with("[node "):
			root = i
			break
	if root < 0:
		return text
	var end := lines.size()
	for i in range(root + 1, lines.size()):
		if lines[i].begins_with("["):
			end = i
			break
	for i in range(root + 1, end):
		if lines[i].begins_with(key + " = "):
			lines[i] = "%s = %s" % [key, value]
			return "\n".join(lines)
	lines.insert(root + 1, "%s = %s" % [key, value])
	return "\n".join(lines)


static func _scenes(folder: String) -> PackedStringArray:
	var out := PackedStringArray()
	for file in DirAccess.get_files_at(folder):
		if file.ends_with(".tscn"):
			out.append(folder.path_join(file))
	for sub in DirAccess.get_directories_at(folder):
		out.append_array(_scenes(folder.path_join(sub)))
	return out


static func _write(path: String, text: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.close()
	return true


static func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for folder in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(folder))
	for file in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(file))
	DirAccess.remove_absolute(path)
