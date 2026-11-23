@tool
class_name AssetLibraryDock
extends EditorDock
## The Asset Library pane: every model the [AssetCatalogue] finds in [code]res://assets/[/code].
## On the left are the sources (the favourites, the recently placed, every pack, or one pack, each
## with its colour) and the chosen source's categories; on the right a search box, body type
## chips, a grid or list of the models with their rendered thumbnails ([AssetThumbnails]), and a
## line about the picked model. What is shown lives in an [AssetLibraryModel], kept per project.
##
## Picking a model arms it for placing: click in the 3D view to place it, Shift and click to keep
## placing, or drag it into the view. A double click or Enter drops it where the view's centre
## meets the ground. Right click for more; F marks a favourite. The pane looks for packs again when
## a model or pack file under [code]res://assets/[/code] changes, or on [b]Refresh[/b].

const DRAG_TYPE := "map_kit_asset"
const SETTING := "asset_library"
## The packs' colours, in the order they are listed, shown faintly behind their models.
const PACK_COLOURS := [Color("#4f8fe8"), Color("#e8a13c"), Color("#5cbf6a"), Color("#c46ad6"),
	Color("#e0635a"), Color("#3fbfbf"), Color("#c9b33f"), Color("#8a8fa3")]
const TINT := 0.16
const SEARCH_DELAY := 0.15
const LIST_ICON := 32
const KIND_TITLES := {obstacle = "Obstacle", vehicle = "Vehicle", pavement = "Pavement",
	looks_only = "Looks only"}
const KIND_TIPS := {obstacle = "Solid things road users see and contact judges: houses, poles.",
	vehicle = "Parked cars, lorries, trains: solid, on the traffic layer.",
	pavement = "Kerbs and road tiles: they stop the car's tyres.",
	looks_only = "Nothing collides with them: paths, awnings, rails."}
enum Menu { PLACE, FAVOURITE, REPLACE, SHOW, COPY }

var plugin: MapKitPlugin
var model := AssetLibraryModel.new()

var _shown: Array[AssetCatalogue.Entry] = []
## Model path to its index in the grid, for thumbnails arriving later.
var _index_of := {}
var _swatches := {}
var _signature := {}
var _sources: ItemList
var _categories: ItemList
var _search: LineEdit
var _search_timer: Timer
var _chips := {}
var _view_button: Button
var _refresh_button: Button
var _size_slider: HSlider
var _grid: ItemList
var _empty: VBoxContainer
var _empty_label: Label
var _empty_button: Button
var _info: Label
var _menu: PopupMenu
var _menu_entry: AssetCatalogue.Entry
var _dragging := false


func _init() -> void:
	title = "Asset Library"
	dock_icon = preload("res://addons/map_kit/icons/map_kit.svg")
	default_slot = DOCK_SLOT_BOTTOM
	available_layouts = DOCK_LAYOUT_HORIZONTAL | DOCK_LAYOUT_VERTICAL | DOCK_LAYOUT_FLOATING
	var split := HSplitContainer.new()
	split.split_offset = 190
	add_child(split)

	var left := VSplitContainer.new()
	left.custom_minimum_size = Vector2(180, 120)
	split.add_child(left)
	_sources = ItemList.new()
	_sources.custom_minimum_size = Vector2(0, 80)
	_sources.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sources.size_flags_stretch_ratio = 0.7
	_sources.item_selected.connect(_on_source_selected)
	left.add_child(_sources)
	_categories = ItemList.new()
	_categories.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_categories.item_selected.connect(_on_category_selected)
	left.add_child(_categories)

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	split.add_child(right)
	var bar := HBoxContainer.new()
	right.add_child(bar)
	_search = LineEdit.new()
	_search.placeholder_text = "Search: words, pack:trains, cat:houses, body:vehicle"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search.custom_minimum_size.x = 160
	_search.text_changed.connect(func(_text: String) -> void: _search_timer.start())
	_search.text_submitted.connect(func(_text: String) -> void: _apply_search())
	bar.add_child(_search)
	_search_timer = Timer.new()
	_search_timer.one_shot = true
	_search_timer.wait_time = SEARCH_DELAY
	_search_timer.timeout.connect(_apply_search)
	add_child(_search_timer)
	for kind in AssetLibraryModel.KINDS:
		var chip := Button.new()
		chip.toggle_mode = true
		chip.text = KIND_TITLES[kind]
		chip.tooltip_text = "Show only: %s\n%s" % [KIND_TITLES[kind].to_lower(), KIND_TIPS[kind]]
		chip.toggled.connect(_on_chip_toggled.bind(kind))
		bar.add_child(chip)
		_chips[kind] = chip
	_view_button = Button.new()
	_view_button.flat = true
	_view_button.toggle_mode = true
	_view_button.tooltip_text = "Show as a list instead of thumbnails."
	_view_button.toggled.connect(_on_view_toggled)
	bar.add_child(_view_button)
	_size_slider = HSlider.new()
	_size_slider.min_value = AssetLibraryModel.THUMB_MIN
	_size_slider.max_value = AssetLibraryModel.THUMB_MAX
	_size_slider.step = 16
	_size_slider.custom_minimum_size = Vector2(80, 0)
	_size_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_size_slider.tooltip_text = "Thumbnail size."
	_size_slider.value_changed.connect(_on_size_changed)
	bar.add_child(_size_slider)
	_refresh_button = Button.new()
	_refresh_button.flat = true
	_refresh_button.text = "Refresh"
	_refresh_button.tooltip_text = "Look for asset packs again."
	_refresh_button.pressed.connect(refresh.bind(true))
	bar.add_child(_refresh_button)

	_grid = ItemList.new()
	_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid.max_text_lines = 2
	_grid.allow_rmb_select = true
	_grid.item_selected.connect(_on_model_selected)
	_grid.item_activated.connect(_on_model_activated)
	_grid.item_clicked.connect(_on_model_clicked)
	_grid.gui_input.connect(_on_grid_input)
	_grid.set_drag_forwarding(_drag_data, Callable(), Callable())
	right.add_child(_grid)
	_empty = VBoxContainer.new()
	_empty.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty.alignment = BoxContainer.ALIGNMENT_CENTER
	_empty.visible = false
	right.add_child(_empty)
	_empty_label = Label.new()
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_empty.add_child(_empty_label)
	_empty_button = Button.new()
	_empty_button.text = "Clear filters"
	_empty_button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_empty_button.pressed.connect(_clear_filters)
	_empty.add_child(_empty_button)
	_info = Label.new()
	_info.modulate = Color(1, 1, 1, 0.75)
	_info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_info.clip_text = true
	right.add_child(_info)

	_menu = PopupMenu.new()
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)


func _ready() -> void:
	if plugin == null:
		return
	var saved: Variant = plugin.setting(SETTING, {})
	if saved is Dictionary:
		model.from_dict(saved)
	_search.text = model.query
	for kind: String in _chips:
		(_chips[kind] as Button).set_pressed_no_signal(model.kinds.has(kind))
	_view_button.set_pressed_no_signal(model.view == AssetLibraryModel.LIST)
	_size_slider.set_value_no_signal(model.thumb_size)
	_apply_icons()
	plugin.placer.armed_changed.connect(_on_armed)
	plugin.placer.placed.connect(_on_placed)
	plugin.placer.turned.connect(_on_turned)
	plugin.thumbnails.thumbnail_ready.connect(_on_thumbnail)
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_filesystem_changed)
	refresh(true)


func _exit_tree() -> void:
	var filesystem := EditorInterface.get_resource_filesystem()
	if filesystem and filesystem.filesystem_changed.is_connected(_on_filesystem_changed):
		filesystem.filesystem_changed.disconnect(_on_filesystem_changed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END and _dragging:
		_dragging = false
		if plugin:
			plugin.end_asset_drag()
	elif what == NOTIFICATION_THEME_CHANGED and is_node_ready():
		_apply_icons()


func _on_filesystem_changed() -> void:
	refresh(false)


## Scans the asset packs again when a model or pack file under [code]res://assets/[/code] changed,
## or always with [param force]; a changed model's mesh and thumbnail are made again.
func refresh(force := false) -> void:
	var signature := _assets_signature()
	if not force and signature == _signature:
		return
	var packs_changed := false
	for path: String in signature:
		if _signature.has(path) and _signature[path] != signature[path]:
			if path.ends_with(AssetPack.FILE):
				packs_changed = true
			else:
				KitModels.forget_model(path)
				if plugin:
					plugin.thumbnails.forget(path)
	if packs_changed or force:
		KitModels.forget()
	_signature = signature
	AssetPack.forget()
	model.set_entries(AssetCatalogue.scan())
	_swatches.clear()
	_list_sources()


func _list_sources() -> void:
	_sources.clear()
	_add_source("★  Favourites  (%d)" % model.favourites.size(), AssetLibraryModel.FAVOURITES,
		"The models marked as favourites: right click a model, or press F.")
	_add_source("⟲  Recent  (%d)" % model.recent.size(), AssetLibraryModel.RECENT,
		"The last %d models placed, newest first." % AssetLibraryModel.RECENT_MAX)
	_add_source("All packs  (%d)" % model.entries.size(), AssetLibraryModel.ALL_PACKS,
		"Every model of every pack.")
	for pack in model.packs:
		var index := _add_source("%s  (%d)" % [pack.short_title(), model.pack_count(pack)],
			pack.title, "%s\n%s" % [pack.title, pack.credit])
		_sources.set_item_icon(index, _swatch(pack))
	var known := false
	for i in _sources.item_count:
		if _sources.get_item_metadata(i) == model.source:
			_sources.select(i)
			known = true
	if not known:
		model.source = AssetLibraryModel.ALL_PACKS
		_sources.select(2)
	_list_categories()


func _add_source(text: String, key: String, tip: String) -> int:
	var index := _sources.add_item(text)
	_sources.set_item_metadata(index, key)
	_sources.set_item_tooltip(index, tip)
	return index


func _list_categories() -> void:
	_categories.clear()
	var listed := model.categories()
	var total := 0
	for pair: Array in listed:
		total += int(pair[1])
	_categories.add_item("All  (%d)" % total)
	_categories.set_item_metadata(0, AssetLibraryModel.ALL)
	var known := model.category == AssetLibraryModel.ALL
	for pair: Array in listed:
		var index := _categories.add_item("%s  (%d)" % pair)
		_categories.set_item_metadata(index, pair[0])
		if pair[0] == model.category:
			_categories.select(index)
			known = true
	if not known:
		model.category = AssetLibraryModel.ALL
	if model.category == AssetLibraryModel.ALL:
		_categories.select(0)
	_show_models()


func _show_models() -> void:
	_grid.clear()
	_index_of.clear()
	if plugin:
		plugin.thumbnails.clear_queue()
	_shown = model.shown()
	var listing := model.view == AssetLibraryModel.LIST
	for entry in _shown:
		var star := "★ " if model.favourites.has(entry.path) else ""
		var text := star + entry.label
		if listing:
			text += "  ·  %s  ·  %s" % [entry.category, entry.pack.short_title()]
		var index := _grid.add_item(text, _thumbnail(entry))
		_grid.set_item_custom_bg_color(index, Color(_colour_of(entry.pack), TINT))
		_grid.set_item_tooltip(index, _describe(entry, "\n", false))
		_index_of[entry.path] = index
	var empty := _shown.is_empty()
	_grid.visible = not empty
	_empty.visible = empty
	if empty:
		_show_empty()
	_info.text = "" if empty else ("%d models. Pick one, then click in the 3D view or drag it "
		+ "there to place it; right click for more.") % _shown.size()


func _show_empty() -> void:
	_empty_button.visible = model.filtered()
	if model.filtered():
		var query := model.query.strip_edges()
		_empty_label.text = ("No models match \"%s\"." % query) if not query.is_empty() \
			else "No models match the filters."
	elif model.source == AssetLibraryModel.FAVOURITES:
		_empty_label.text = "No favourites yet: right click a model and add it, or pick it and press F."
	elif model.source == AssetLibraryModel.RECENT:
		_empty_label.text = "Nothing placed yet. The models placed show here, newest first."
	else:
		_empty_label.text = "No models here. Drop a pack folder under res://assets/, then Refresh."


## The thumbnail to show now: the rendered one if ready, else the pack's preview, else the
## editor's own preview when it comes.
func _thumbnail(entry: AssetCatalogue.Entry) -> Texture2D:
	var rendered := plugin.thumbnails.get_thumbnail(entry.path) if plugin else null
	if rendered:
		return rendered
	if not entry.preview.is_empty():
		return load(entry.preview)
	if plugin:
		EditorInterface.get_resource_previewer().queue_resource_preview(entry.path, self,
			&"_on_preview", null)
	return _placeholder()


func _on_thumbnail(path: String, texture: Texture2D) -> void:
	var index: int = _index_of.get(path, -1)
	if index >= 0 and index < _grid.item_count:
		_grid.set_item_icon(index, texture)


func _on_preview(path: String, preview: Texture2D, _thumbnail_preview: Texture2D,
		_data: Variant) -> void:
	var index: int = _index_of.get(path, -1)
	if preview and index >= 0 and index < _grid.item_count \
			and plugin.thumbnails.get_thumbnail(path) == null:
		_grid.set_item_icon(index, preview)


func _on_source_selected(index: int) -> void:
	model.source = _sources.get_item_metadata(index)
	_save()
	_list_categories()


func _on_category_selected(index: int) -> void:
	model.category = _categories.get_item_metadata(index)
	_save()
	_show_models()


func _apply_search() -> void:
	_search_timer.stop()
	if model.query == _search.text:
		return
	model.query = _search.text
	_save()
	_show_models()


func _on_chip_toggled(on: bool, kind: String) -> void:
	var kinds := model.kinds
	if on and not kinds.has(kind):
		kinds.append(kind)
	elif not on and kinds.has(kind):
		kinds.remove_at(kinds.find(kind))
	model.kinds = kinds
	_save()
	_show_models()


func _on_view_toggled(listing: bool) -> void:
	model.view = AssetLibraryModel.LIST if listing else AssetLibraryModel.GRID
	_save()
	_apply_view()
	_show_models()


func _on_size_changed(value: float) -> void:
	model.thumb_size = int(value)
	_save()
	_apply_view()


func _clear_filters() -> void:
	model.clear_filters()
	_search.text = ""
	for chip: Button in _chips.values():
		chip.set_pressed_no_signal(false)
	_save()
	_list_categories()


func _on_model_selected(index: int) -> void:
	var entry := _shown[index]
	_info.text = _describe(entry, "  ·  ", true)
	if plugin.edited_map() == null:
		_info.text += "  ·  Open a map to place it."
		return
	plugin.placer.arm(_piece(entry))


func _on_model_activated(index: int) -> void:
	_place_at_centre(_shown[index])


func _on_model_clicked(index: int, at: Vector2, button: int) -> void:
	if button != MOUSE_BUTTON_RIGHT:
		return
	_menu_entry = _shown[index]
	_menu.clear()
	var map_open := plugin.edited_map() != null
	_menu.add_item("Place at view centre", Menu.PLACE)
	_menu.set_item_disabled(_menu.get_item_index(Menu.PLACE), not map_open)
	_menu.add_item("Remove from favourites" if model.favourites.has(_menu_entry.path)
		else "Add to favourites", Menu.FAVOURITE)
	_menu.add_item("Replace selected map assets", Menu.REPLACE)
	_menu.set_item_disabled(_menu.get_item_index(Menu.REPLACE), not map_open)
	_menu.add_separator()
	_menu.add_item("Show in FileSystem", Menu.SHOW)
	_menu.add_item("Copy path", Menu.COPY)
	_menu.position = Vector2i(_grid.get_screen_position() + at)
	_menu.reset_size()
	_menu.popup()


func _on_menu(id: int) -> void:
	var entry := _menu_entry
	if entry == null:
		return
	match id:
		Menu.PLACE:
			_place_at_centre(entry)
		Menu.FAVOURITE:
			_toggle_favourite(entry)
		Menu.REPLACE:
			_replace_selection(entry)
		Menu.SHOW:
			EditorInterface.select_file(entry.path)
		Menu.COPY:
			DisplayServer.clipboard_set(entry.path)


func _on_grid_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key and key.pressed and not key.echo and key.keycode == KEY_F \
			and not key.ctrl_pressed and not key.alt_pressed:
		var picked := _grid.get_selected_items()
		if not picked.is_empty():
			_toggle_favourite(_shown[picked[0]])
			_grid.accept_event()


func _toggle_favourite(entry: AssetCatalogue.Entry) -> void:
	var now := model.toggle_favourite(entry.path)
	_save()
	_info.text = "%s %s favourites." % [entry.label, "added to" if now else "removed from"]
	_list_sources()


func _place_at_centre(entry: AssetCatalogue.Entry) -> void:
	var road_map := plugin.edited_map()
	if road_map == null:
		_info.text = "Open a map to place %s." % entry.label
		return
	plugin.placer.drop_at_centre(road_map, _piece(entry))


func _on_armed(piece: MapKitTools.Piece) -> void:
	if piece == null or not piece.has_meta(&"asset"):
		_grid.deselect_all()


func _on_placed(piece: MapKitTools.Piece) -> void:
	if not piece.has_meta(&"asset"):
		return
	model.push_recent(piece.get_meta(&"asset"))
	_save()
	_sources.set_item_text(1, "⟲  Recent  (%d)" % model.recent.size())
	if model.source == AssetLibraryModel.RECENT:
		_show_models()


func _on_turned(piece: MapKitTools.Piece, turn: float) -> void:
	if piece.has_meta(&"asset"):
		model.set_turn(piece.get_meta(&"asset"), turn)
		_save()


func _replace_selection(entry: AssetCatalogue.Entry) -> void:
	var edit := MapKitTools.Edit.new()
	for node in EditorInterface.get_selection().get_top_selected_nodes():
		if node is MapAsset:
			AssetTools.set_model(edit, node as MapAsset, entry)
	if not plugin.apply(edit, "Replace with %s" % entry.label):
		_info.text = "Select map assets in the scene to replace."


## The palette piece placing [param entry], turned as it was last placed.
func _piece(entry: AssetCatalogue.Entry) -> MapKitTools.Piece:
	var piece := MapKitTools.Piece.new(entry.label, entry.category, "Props",
		func() -> Node3D: return AssetCatalogue.make(entry), entry.preview)
	piece.set_meta(&"asset", entry.path)
	piece.turn = model.turn_of(entry.path)
	return piece


func _drag_data(at: Vector2) -> Variant:
	var index := _grid.get_item_at_position(at, true)
	if index < 0 or plugin == null:
		return null
	var entry := _shown[index]
	var picture := TextureRect.new()
	picture.texture = _grid.get_item_icon(index)
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.size = Vector2(64, 64)
	picture.modulate = Color(1, 1, 1, 0.8)
	_grid.set_drag_preview(picture)
	_dragging = true
	plugin.begin_asset_drag(_piece(entry))
	return {type = DRAG_TYPE, path = entry.path}


## The model's label, category, pack and credit, kind, and turn, joined by [param separator];
## with [param measured], its size and triangles too, which builds its mesh.
func _describe(entry: AssetCatalogue.Entry, separator: String, measured: bool) -> String:
	var parts := PackedStringArray([entry.label, entry.category,
		entry.pack.title + ("" if entry.pack.credit.is_empty() else " (%s)" % entry.pack.credit),
		entry.body_title()])
	if measured:
		var size := AssetCatalogue.shown_size(entry)
		parts.append("%.1f × %.1f × %.1f m" % [size.x, size.y, size.z])
		parts.append("%d triangles" % KitModels.triangles(entry.path))
	var turn := model.turn_of(entry.path)
	if not is_zero_approx(turn):
		parts.append("turned %d°" % roundi(rad_to_deg(turn)))
	if model.favourites.has(entry.path):
		parts.append("favourite")
	return separator.join(parts)


func _save() -> void:
	if plugin:
		plugin.set_setting(SETTING, model.to_dict())


func _apply_view() -> void:
	if model.view == AssetLibraryModel.LIST:
		_grid.icon_mode = ItemList.ICON_MODE_LEFT
		_grid.max_columns = 1
		_grid.same_column_width = false
		_grid.fixed_column_width = 0
		_grid.fixed_icon_size = Vector2i(LIST_ICON, LIST_ICON)
		_grid.max_text_lines = 1
	else:
		_grid.icon_mode = ItemList.ICON_MODE_TOP
		_grid.max_columns = 0
		_grid.same_column_width = true
		_grid.fixed_icon_size = Vector2i(model.thumb_size, model.thumb_size)
		_grid.fixed_column_width = model.thumb_size + 40
		_grid.max_text_lines = 2
	_size_slider.editable = model.view == AssetLibraryModel.GRID


func _apply_icons() -> void:
	if plugin and EditorInterface.get_editor_theme():
		_view_button.icon = MapKitDock.editor_icon(&"FileList")
		_search.right_icon = MapKitDock.editor_icon(&"Search")
		_refresh_button.icon = MapKitDock.editor_icon(&"Reload")
		_refresh_button.text = ""
	_apply_view()


## Each model and pack file under [code]res://assets/[/code] with its modified time.
static func _assets_signature(folder := AssetCatalogue.ROOT.trim_suffix("/")) -> Dictionary:
	var out := {}
	for file in DirAccess.get_files_at(folder):
		if file.get_extension() == "glb" or file == AssetPack.FILE:
			var path := folder.path_join(file)
			out[path] = FileAccess.get_modified_time(path)
	for sub in DirAccess.get_directories_at(folder):
		if not sub.begins_with(".") and sub != "previews" and sub != "Textures":
			out.merge(_assets_signature(folder.path_join(sub)))
	return out


func _colour_of(pack: AssetPack) -> Color:
	var index := model.packs.find(pack)
	return PACK_COLOURS[index % PACK_COLOURS.size()] if index >= 0 else Color.GRAY


## A small square of [param pack]'s colour, made once.
func _swatch(pack: AssetPack) -> Texture2D:
	if not _swatches.has(pack):
		var image := Image.create(12, 12, false, Image.FORMAT_RGBA8)
		image.fill(_colour_of(pack))
		_swatches[pack] = ImageTexture.create_from_image(image)
	return _swatches[pack]


func _placeholder() -> Texture2D:
	return MapKitDock.editor_icon(&"MeshInstance3D") if plugin else null
