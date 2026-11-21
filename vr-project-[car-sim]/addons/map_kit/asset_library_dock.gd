@tool
class_name AssetLibraryDock
extends EditorDock
## The Asset Library pane: every model the [AssetCatalogue] finds in [code]res://assets/[/code], by
## category on the left (Cars, Vans and lorries, Houses, Trees, ...) and as thumbnails on the
## right, with a search box. Selecting a model arms it for placing: click in the 3D view to place
## it as a [MapAsset], Shift+click to keep placing; a double click drops it where the view's
## centre meets the ground. [b]Replace selection[/b] gives the selected map assets the model
## instead. A new pack folder shows up when the filesystem changes or on [b]Refresh[/b].

const ALL := "All"
const THUMB_SIZES := [48, 64, 96, 128]

var plugin: MapKitPlugin

var _entries: Array[AssetCatalogue.Entry] = []
var _shown: Array[AssetCatalogue.Entry] = []
var _categories: ItemList
var _search: LineEdit
var _grid: ItemList
var _info: Label
var _thumb := 64


func _init() -> void:
	title = "Asset Library"
	dock_icon = preload("res://addons/map_kit/icons/map_kit.svg")
	default_slot = DOCK_SLOT_BOTTOM
	available_layouts = DOCK_LAYOUT_HORIZONTAL | DOCK_LAYOUT_VERTICAL | DOCK_LAYOUT_FLOATING
	var split := HSplitContainer.new()
	split.split_offset = 180
	add_child(split)
	_categories = ItemList.new()
	_categories.custom_minimum_size = Vector2(160, 120)
	_categories.item_selected.connect(func(_index: int) -> void: _show_models())
	split.add_child(_categories)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	var bar := HBoxContainer.new()
	_search = LineEdit.new()
	_search.placeholder_text = "Search models"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_text: String) -> void: _show_models())
	bar.add_child(_search)
	var size_pick := OptionButton.new()
	for thumb: int in THUMB_SIZES:
		size_pick.add_item("%d px" % thumb)
	size_pick.select(THUMB_SIZES.find(_thumb))
	size_pick.tooltip_text = "Thumbnail size."
	size_pick.item_selected.connect(func(index: int) -> void:
		_thumb = THUMB_SIZES[index]
		_apply_thumb_size())
	bar.add_child(size_pick)
	bar.add_child(_button("Replace selection", _replace_selection,
		"Gives the selected map assets this model, set up as its category says."))
	bar.add_child(_button("Refresh", refresh, "Looks for asset packs again."))
	right.add_child(bar)
	_grid = ItemList.new()
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid.max_columns = 0
	_grid.icon_mode = ItemList.ICON_MODE_TOP
	_grid.same_column_width = true
	_grid.max_text_lines = 2
	_grid.item_selected.connect(_on_model_selected)
	_grid.item_activated.connect(_on_model_activated)
	right.add_child(_grid)
	_info = Label.new()
	_info.modulate = Color(1, 1, 1, 0.7)
	_info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_info.clip_text = true
	right.add_child(_info)
	_apply_thumb_size()


func _ready() -> void:
	if plugin == null:
		return
	plugin.placer.armed_changed.connect(_on_armed)
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(refresh)
	refresh()


func _exit_tree() -> void:
	var filesystem := EditorInterface.get_resource_filesystem()
	if filesystem and filesystem.filesystem_changed.is_connected(refresh):
		filesystem.filesystem_changed.disconnect(refresh)


## Scans the asset packs again, keeping the chosen category where it still exists.
func refresh() -> void:
	AssetPack.forget()
	var chosen := _chosen_category()
	_entries = AssetCatalogue.scan()
	_categories.clear()
	var counts := {}
	for entry in _entries:
		counts[entry.category] = counts.get(entry.category, 0) + 1
	_categories.add_item("%s  (%d)" % [ALL, _entries.size()])
	_categories.set_item_metadata(0, ALL)
	for category in AssetCatalogue.categories(_entries):
		var index := _categories.add_item("%s  (%d)" % [category, counts[category]])
		_categories.set_item_metadata(index, category)
	var select := 0
	for i in _categories.item_count:
		if _categories.get_item_metadata(i) == chosen:
			select = i
	_categories.select(select)
	_show_models()


func _show_models() -> void:
	var category := _chosen_category()
	var query := _search.text.strip_edges().to_lower()
	_grid.clear()
	_shown.clear()
	for entry in _entries:
		if category != ALL and entry.category != category:
			continue
		if not query.is_empty() and not entry.label.to_lower().contains(query) \
				and not entry.category.to_lower().contains(query):
			continue
		var index := _grid.add_item(entry.label, _placeholder())
		_grid.set_item_tooltip(index, "%s\n%s · %s\n%s" % [entry.label, entry.category,
			entry.pack.title, entry.body_title()])
		_shown.append(entry)
		if not entry.preview.is_empty():
			_grid.set_item_icon(index, load(entry.preview))
		else:
			EditorInterface.get_resource_previewer().queue_resource_preview(entry.path, self,
				&"_on_preview", index)
	_info.text = "%d models. Pick one, then click in the 3D view to place it." % _shown.size() \
		if not _shown.is_empty() else "No models match."


func _on_preview(path: String, preview: Texture2D, _thumbnail: Texture2D, index: int) -> void:
	if preview and index < _shown.size() and _shown[index].path == path:
		_grid.set_item_icon(index, preview)


func _on_model_selected(index: int) -> void:
	var entry := _shown[index]
	var size := KitModels.size_of(entry.path) * AssetCatalogue.make(entry).model_scale()
	_info.text = "%s · %s · %s · %.1f × %.1f × %.1f m · %s" % [entry.label, entry.category,
		entry.body_title().to_lower(), size.x, size.y,
		size.z, entry.pack.credit if not entry.pack.credit.is_empty() else entry.pack.title]
	if plugin.edited_map() == null:
		_info.text += "  ·  Open a map to place it."
		return
	plugin.placer.arm(_piece(entry))


func _on_model_activated(index: int) -> void:
	var road_map := plugin.edited_map()
	if road_map == null:
		return
	plugin.placer.arm(_piece(_shown[index]))
	plugin.placer.place(road_map, plugin.dock.view_centre(road_map))
	plugin.placer.disarm()


func _on_armed(piece: MapKitTools.Piece) -> void:
	if piece == null or not piece.has_meta(&"asset"):
		_grid.deselect_all()


func _replace_selection() -> void:
	var picked := _grid.get_selected_items()
	if picked.is_empty():
		_info.text = "Pick a model first."
		return
	var entry := _shown[picked[0]]
	var template := AssetCatalogue.make(entry)
	var edit := MapKitTools.Edit.new()
	for node in EditorInterface.get_selection().get_top_selected_nodes():
		if node is MapAsset:
			for property: StringName in [&"model", &"solid", &"fit", &"extra_scale",
					&"solid_part"]:
				edit.set_value(node, property, template.get(property))
	template.free()
	if not plugin.apply(edit, "Replace with %s" % entry.label):
		_info.text = "Select map assets in the scene to replace."


## The palette piece placing [param entry].
func _piece(entry: AssetCatalogue.Entry) -> MapKitTools.Piece:
	var piece := MapKitTools.Piece.new(entry.label, entry.category, "Props",
		func() -> Node3D: return AssetCatalogue.make(entry), entry.preview)
	piece.set_meta(&"asset", entry.path)
	return piece


func _chosen_category() -> String:
	var picked := _categories.get_selected_items() if _categories else PackedInt32Array()
	return _categories.get_item_metadata(picked[0]) if not picked.is_empty() else ALL


func _apply_thumb_size() -> void:
	_grid.fixed_icon_size = Vector2i(_thumb, _thumb)
	_grid.fixed_column_width = _thumb + 40


func _placeholder() -> Texture2D:
	var theme := EditorInterface.get_editor_theme()
	return theme.get_icon(&"MeshInstance3D", &"EditorIcons") if theme else null


static func _button(text: String, pressed: Callable, tip: String) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	button.pressed.connect(pressed)
	return button
