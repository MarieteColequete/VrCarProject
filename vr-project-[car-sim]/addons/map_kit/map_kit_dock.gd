@tool
class_name MapKitDock
extends EditorDock
## The Map Kit dock: the controls only, in folding sections, each remembering whether it is open.
## [br]- Open map: the open map's title and description, edited with undo; save and play it.
## [br]- Maps: every map the [MapCatalogue] finds; create, open, play, rename, duplicate, or
## delete one (also from its right-click menu).
## [br]- Problems: the open map's problems, kept current as it is edited, each with its fix where
## one is known; selecting one selects its node.
## [br]- Selection: set meshes as road, give them a solid body, link lanes, snap to the grid, add
## terrain, and drape roads and places on it.
## [br]- Terrain shape: shown while one [TerrainShape] is selected; its kind, height, size and
## falloff with sliders (a drag is one undo action), and standing its base on the land.
## [br]- Palette: pieces to place by clicking in the 3D view, with a search box.
## [br]- View: the overlay, the Dev HUD when playing, and the grid step.
## [br]The work is the [MapKitPlugin]'s and [MapKitTools]'.

const SANDBOX := "res://scenarios/debug/map_sandbox.tscn"
## Seconds a message stays in the status line.
const STATUS_TIME := 6.0
## The steepest a draped road climbs, rise over run.
const MAX_GRADE := 0.12
const MAP_ICON := preload("res://addons/map_kit/icons/map_kit.svg")

var plugin: MapKitPlugin

var _sections: Array[FoldableContainer] = []
var _status: Label
var _status_timer: Timer

var _map_form: Control
var _no_map: Label
var _title: LineEdit
var _id: Label
var _description: TextEdit

var _new_name: LineEdit
var _maps: ItemList
var _map_menu: PopupMenu
var _name_dialog: ConfirmationDialog
var _name_field: LineEdit
var _title_field: LineEdit
var _delete_dialog: ConfirmationDialog
var _pending := {}

var _problems_section: FoldableContainer
var _problem_rows: VBoxContainer
var _fix_all: Button

var _search: LineEdit
var _palette: VBoxContainer
var _palette_buttons: Array[Button] = []
var _palette_group := ButtonGroup.new()
var _place_hint: Label

var _shape_section: FoldableContainer
var _shape: TerrainShape
var _shape_kind: OptionButton
var _shape_note: Label
var _shape_sliders := {}

var _overlay_box: CheckBox
var _dev_hud_box: CheckBox
var _grid_step: SpinBox


func _init() -> void:
	title = "Map Kit"
	dock_icon = MAP_ICON
	default_slot = DOCK_SLOT_RIGHT_UL
	available_layouts = DOCK_LAYOUT_VERTICAL | DOCK_LAYOUT_FLOATING
	var outer := VBoxContainer.new()
	add_child(outer)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override(&"separation", 6)
	scroll.add_child(column)
	_build_open_map(column)
	_build_maps(column)
	_build_problems(column)
	_build_selection(column)
	_build_shape(column)
	_build_road_users(column)
	_build_palette(column)
	_build_view(column)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.modulate = Color(1, 1, 1, 0.8)
	outer.add_child(_status)
	_status_timer = Timer.new()
	_status_timer.one_shot = true
	_status_timer.timeout.connect(func() -> void: _status.text = "")
	add_child(_status_timer)
	_build_dialogs()


func _ready() -> void:
	if plugin == null:
		return
	for section in _sections:
		section.folded = plugin.setting("folded/" + section.title.get_slice(" (", 0),
			section.folded)
		section.folding_changed.connect(func(folded: bool) -> void:
			plugin.set_setting("folded/" + section.title.get_slice(" (", 0), folded))
	plugin.problems_changed.connect(show_problems)
	plugin.placer.armed_changed.connect(_on_armed)
	EditorInterface.get_selection().selection_changed.connect(_on_selection_changed)
	_on_selection_changed()
	EditorInterface.get_resource_filesystem().filesystem_changed.connect(refresh_maps)
	_overlay_box.set_pressed_no_signal(plugin.setting("overlay", true))
	_dev_hud_box.set_pressed_no_signal(plugin.setting("dev_hud", false))
	_grid_step.set_value_no_signal(plugin.setting("grid_step", 0.5))
	refresh_maps()
	show_open_map()
	show_problems(plugin.problems)


func _exit_tree() -> void:
	var selection := EditorInterface.get_selection()
	if selection and selection.selection_changed.is_connected(_on_selection_changed):
		selection.selection_changed.disconnect(_on_selection_changed)
	_watch_shape(null)
	var filesystem := EditorInterface.get_resource_filesystem()
	if filesystem and filesystem.filesystem_changed.is_connected(refresh_maps):
		filesystem.filesystem_changed.disconnect(refresh_maps)


## Lists the maps the [MapCatalogue] finds.
func refresh_maps() -> void:
	var selected := _selected_map()
	_maps.clear()
	for entry in MapCatalogue.scan():
		var index := _maps.add_item("%s  (%s)" % [entry.title, entry.id], MAP_ICON)
		_maps.set_item_metadata(index, entry.path)
		_maps.set_item_tooltip(index, entry.path)
		if entry.path == selected:
			_maps.select(index)


## Shows the open map's title, id, and description; a note when no map is open.
func show_open_map() -> void:
	var road_map: RoadMap = plugin.edited_map() if plugin else null
	_map_form.visible = road_map != null
	_no_map.visible = road_map == null
	if road_map == null:
		return
	if not _title.has_focus():
		_title.text = road_map.title
	_id.text = "%s  ·  %s" % [road_map.id, road_map.scene_file_path]
	if not _description.has_focus():
		_description.text = road_map.description


## Lists [param problems], warnings first, each with its fix where it has one.
func show_problems(problems: Array[Dictionary]) -> void:
	for row in _problem_rows.get_children():
		row.queue_free()
	var warnings := problems.filter(func(p: Dictionary) -> bool:
		return p.severity == MapKitTools.WARNING)
	var notices := problems.filter(func(p: Dictionary) -> bool:
		return p.severity != MapKitTools.WARNING)
	_problems_section.title = "Problems (%d)" % problems.size() if not problems.is_empty() \
		else "Problems"
	title = "Map Kit (%d)" % warnings.size() if not warnings.is_empty() else "Map Kit"
	_fix_all.disabled = not problems.any(func(p: Dictionary) -> bool: return p.fix != null)
	if plugin and plugin.edited_map() == null:
		_problem_rows.add_child(_note("Open a map to check it."))
		return
	if problems.is_empty():
		var clear := _note("No problems found.")
		clear.add_theme_color_override(&"font_color", MapKitOverlay.LINKED)
		_problem_rows.add_child(clear)
		return
	for problem: Dictionary in warnings + notices:
		_problem_rows.add_child(_problem_row(problem))


func _problem_row(problem: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var icon := TextureRect.new()
	icon.texture = _editor_icon(&"StatusWarning" if problem.severity == MapKitTools.WARNING
		else &"NodeInfo")
	icon.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	icon.tooltip_text = "Warning" if problem.severity == MapKitTools.WARNING else "Notice"
	row.add_child(icon)
	var node: Node = problem.node
	var text := Button.new()
	text.flat = true
	text.alignment = HORIZONTAL_ALIGNMENT_LEFT
	text.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	text.clip_text = true
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.text = "%s: %s" % [node.name, problem.message]
	text.tooltip_text = "%s\n%s\nClick to select it." % [node.name, problem.message]
	text.pressed.connect(_select.bind(node))
	row.add_child(text)
	if problem.fix != null:
		var action := "%s for %s" % [problem.fix_label, node.name]
		row.add_child(_button(problem.fix_label, func() -> void:
			plugin.apply((problem.fix as Callable).call(), action),
			"Fix it: %s." % problem.fix_label.to_lower()))
	return row


func _build_open_map(column: VBoxContainer) -> void:
	var box := _section(column, "Open map")
	_no_map = _note("Open a map scene, or create one under Maps.")
	box.add_child(_no_map)
	var form := VBoxContainer.new()
	_map_form = form
	box.add_child(form)
	_title = LineEdit.new()
	_title.placeholder_text = "Title"
	_title.tooltip_text = "The name players see. Press Enter to set it."
	_title.text_submitted.connect(func(_text: String) -> void: _commit_title())
	_title.focus_exited.connect(_commit_title)
	form.add_child(_title)
	_id = Label.new()
	_id.modulate = Color(1, 1, 1, 0.6)
	_id.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_id.clip_text = true
	_id.tooltip_text = "The map's id and scene; rename the map under Maps to change them."
	form.add_child(_id)
	_description = TextEdit.new()
	_description.placeholder_text = "What the map is for, in a sentence or two."
	_description.custom_minimum_size.y = 56
	_description.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_description.focus_exited.connect(_commit_description)
	form.add_child(_description)
	var actions := HFlowContainer.new()
	actions.add_child(_button("Save", func() -> void: EditorInterface.save_scene(),
		"Saves the map.", &"Save"))
	actions.add_child(_button("Play", _play_open, "Saves the map and drives it in free drive.",
		&"Play"))
	form.add_child(actions)


func _build_maps(column: VBoxContainer) -> void:
	var box := _section(column, "Maps")
	var row := HBoxContainer.new()
	_new_name = LineEdit.new()
	_new_name.placeholder_text = "new_map_name"
	_new_name.tooltip_text = "Lower case letters, digits, and underscores, starting with a letter."
	_new_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_new_name.text_submitted.connect(func(_text: String) -> void: _create_map())
	row.add_child(_new_name)
	row.add_child(_button("Create", _create_map, "Creates the map from the map base and opens it.",
		&"Add"))
	box.add_child(row)
	_maps = ItemList.new()
	_maps.custom_minimum_size.y = 170
	_maps.allow_rmb_select = true
	_maps.item_activated.connect(func(index: int) -> void:
		_open_map(_maps.get_item_metadata(index)))
	_maps.item_clicked.connect(_on_map_clicked)
	box.add_child(_maps)
	var actions := HFlowContainer.new()
	actions.add_child(_button("Open", func() -> void: _open_map(_selected_map()),
		"Opens the selected map. A double click does too.", &"Load"))
	actions.add_child(_button("Play", func() -> void: _play_map(_selected_map()),
		"Drives the selected map in free drive.", &"Play"))
	actions.add_child(_button("Rename", func() -> void: _ask_name(&"rename"),
		"Renames the selected map's folder, scene, and id, and the scenarios using it.", &"Rename"))
	actions.add_child(_button("Duplicate", func() -> void: _ask_name(&"duplicate"),
		"Copies the selected map under a new name.", &"Duplicate"))
	actions.add_child(_button("Delete", _ask_delete,
		"Moves the selected map to the trash, unless a scenario uses it.", &"Remove"))
	actions.add_child(_button("", refresh_maps, "Looks for maps again.", &"Reload"))
	box.add_child(actions)
	_map_menu = PopupMenu.new()
	for item: Array in [["Open", &"Load"], ["Play", &"Play"], ["Rename", &"Rename"],
			["Duplicate", &"Duplicate"], ["Delete", &"Remove"],
			["Show in FileSystem", &"Filesystem"]]:
		_map_menu.add_icon_item(_editor_icon(item[1]), item[0])
	_map_menu.id_pressed.connect(_on_map_menu)
	add_child(_map_menu)


func _build_problems(column: VBoxContainer) -> void:
	var box := _section(column, "Problems")
	_problems_section = box.get_parent() as FoldableContainer
	_problem_rows = VBoxContainer.new()
	box.add_child(_problem_rows)
	var actions := HFlowContainer.new()
	_fix_all = _button("Fix all", _fix_everything, "Applies every fix listed, as one undo step.")
	actions.add_child(_fix_all)
	actions.add_child(_button("Check now", func() -> void: plugin.check_now(),
		"Lists the open map's problems again; it also happens by itself as the map is edited.",
		&"Reload"))
	box.add_child(actions)


func _build_selection(column: VBoxContainer) -> void:
	var box := _section(column, "Selection")
	var flow := HFlowContainer.new()
	flow.add_child(_button("Set as road", _set_as_road,
		"Gives the selected meshes the asphalt material."))
	flow.add_child(_button("Set as obstacle", _set_as_obstacle,
		"Gives the selected nodes a solid box on the obstacle layer: the car hits them, road "
		+ "users see them, and touching them is a fault."))
	flow.add_child(_button("Connect lanes", _connect_lanes,
		"Links each lane to the lanes starting where it ends: the selected ones, or all the "
		+ "map's."))
	flow.add_child(_button("Snap to grid", _snap, "Moves the selected nodes onto the grid.",
		&"Snap"))
	flow.add_child(_button("Drape on terrain", _drape,
		"Sets the selected roads, lanes, markings, spawns, props, and assets (or the whole map's) "
		+ "on the terrain's land, the roads no steeper than %d%%." % roundi(MAX_GRADE * 100.0),
		&"CurveTexture"))
	flow.add_child(_button("Add terrain", _add_terrain,
		"Adds land that is not flat, shaped by a heightmap and the Terrain pieces, and turns the "
		+ "flat ground off."))
	flow.add_child(_button("Next look", _next_look,
		"Shows the next car, van, or house on the selected props, the next kind of the selected "
		+ "scenery, and the next model of the selected map assets' category."))
	box.add_child(flow)


func _build_shape(column: VBoxContainer) -> void:
	var box := _section(column, "Terrain shape")
	_shape_section = box.get_parent() as FoldableContainer
	_shape_section.visible = false
	_shape_kind = OptionButton.new()
	for label: String in MapKitTools.SHAPE_NOTES:
		_shape_kind.add_item(label, TerrainShape.Kind[label.to_upper()])
	_shape_kind.item_selected.connect(func(index: int) -> void:
		_set_shape(&"kind", _shape_kind.get_item_id(index), false))
	box.add_child(_shape_kind)
	_shape_note = _note("")
	box.add_child(_shape_note)
	var limits := {TerrainShape.HEIGHT: [-50.0, 50.0], TerrainShape.RADIUS: [0.0, 200.0],
		TerrainShape.LENGTH: [1.0, 400.0], TerrainShape.WIDTH: [1.0, 200.0],
		TerrainShape.FALLOFF: [0.0, 200.0]}
	for field: StringName in limits:
		var slider := EditorSpinSlider.new()
		slider.label = String(field).capitalize()
		slider.suffix = "m"
		slider.min_value = limits[field][0]
		slider.max_value = limits[field][1]
		slider.step = 0.1
		slider.allow_greater = true
		slider.allow_lesser = field == TerrainShape.HEIGHT
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.value_changed.connect(func(value: float) -> void: _set_shape(field, value, true))
		box.add_child(slider)
		_shape_sliders[field] = slider
	box.add_child(_button("Stand on the land", _snap_shape,
		"Moves the shape's base onto the land under it, the land without this shape, so a "
		+ "plateau's or a ramp's height counts from the ground.", &"ToolMove"))
	box.add_child(_note("Drag its handles in the 3D view: the radius and falloff on the land, "
		+ "the height on its marker. Shift snaps finer."))


func _on_selection_changed() -> void:
	var picked := _selected()
	_watch_shape(picked[0] as TerrainShape if picked.size() == 1 else null)


## Shows [param shape] in the Terrain shape section and follows its changes; hides the section
## for none.
func _watch_shape(shape: TerrainShape) -> void:
	if _shape == shape:
		return
	if is_instance_valid(_shape) and _shape.shape_changed.is_connected(_show_shape):
		_shape.shape_changed.disconnect(_show_shape)
	_shape = shape
	if _shape:
		_shape.shape_changed.connect(_show_shape)
	if _shape_section:
		_shape_section.visible = _shape != null
	_show_shape()


func _show_shape() -> void:
	if _shape == null or not is_instance_valid(_shape):
		return
	_shape_kind.select(_shape_kind.get_item_index(_shape.kind))
	var label := _shape_kind.get_item_text(_shape_kind.selected)
	_shape_note.text = MapKitTools.SHAPE_NOTES.get(label, "")
	var fields := MapKitTools.shape_fields(_shape.kind)
	for field: StringName in _shape_sliders:
		var slider: EditorSpinSlider = _shape_sliders[field]
		slider.visible = fields.has(field)
		slider.set_value_no_signal(_shape.handle_value(field))


func _set_shape(field: StringName, value: float, merge: bool) -> void:
	if _shape == null or not is_instance_valid(_shape):
		return
	var named := "kind" if field == &"kind" else String(field).capitalize().to_lower()
	plugin.apply(MapKitTools.set_shape(_shape, field, value), "Set terrain shape's " + named,
		false, merge)


func _snap_shape() -> void:
	var road_map := _need_map()
	if road_map == null or _shape == null:
		return
	if Terrain.of(road_map) == null:
		_say("The map has no terrain: press Add terrain first.")
		return
	plugin.apply(MapKitTools.snap_shape_base(road_map, _shape), "Stand terrain shape on the land")


func _build_road_users(column: VBoxContainer) -> void:
	var box := _section(column, "Road users")
	box.add_child(_note("Select one or more cars (from the Asset Library, or road users already) "
		+ "and a checkpoint, then press Drive to checkpoint. Each becomes a road user that drives "
		+ "along the lanes to it, keeping the rules and reacting to traffic, and stops there."))
	var flow := HFlowContainer.new()
	flow.add_child(_button("Drive to checkpoint", _drive_to,
		"Turns the selected cars into road users driving to the selected checkpoint, or the "
		+ "map's only one."))
	box.add_child(flow)


func _build_palette(column: VBoxContainer) -> void:
	var box := _section(column, "Palette")
	_search = LineEdit.new()
	_search.placeholder_text = "Search pieces"
	_search.clear_button_enabled = true
	_search.right_icon = _editor_icon(&"Search")
	_search.text_changed.connect(_filter_palette)
	box.add_child(_search)
	_place_hint = _note("Pick a piece, then click in the 3D view to place it. Shift+click keeps "
		+ "placing, R turns it, Esc stops. Double click a piece to drop it at the view's centre.")
	box.add_child(_place_hint)
	_palette = VBoxContainer.new()
	box.add_child(_palette)
	var section := ""
	var flow: HFlowContainer
	for piece in MapKitTools.pieces():
		if piece.section != section:
			section = piece.section
			var heading := Label.new()
			heading.text = section
			heading.modulate = Color(1, 1, 1, 0.7)
			_palette.add_child(heading)
			flow = HFlowContainer.new()
			_palette.add_child(flow)
		var button := _button(piece.label, Callable(), piece.tip)
		button.icon = _piece_icon(piece)
		button.add_theme_constant_override(&"icon_max_width", 20)
		button.toggle_mode = true
		button.button_group = _palette_group
		button.set_meta(&"piece", piece)
		button.toggled.connect(_on_piece_toggled.bind(piece))
		button.gui_input.connect(_on_piece_input.bind(piece))
		flow.add_child(button)
		_palette_buttons.append(button)
	_palette_group.allow_unpress = true


func _build_view(column: VBoxContainer) -> void:
	var box := _section(column, "View")
	_overlay_box = CheckBox.new()
	_overlay_box.text = "Overlay in the 3D view"
	_overlay_box.tooltip_text = "Lane arrows, lane ends (green leads on, red leads nowhere), " \
		+ "open road ends, spawns, zones, and the problem count. Also on the 3D view's toolbar."
	_overlay_box.toggled.connect(func(on: bool) -> void: plugin.set_overlay(on))
	box.add_child(_overlay_box)
	_dev_hud_box = CheckBox.new()
	_dev_hud_box.text = "Dev HUD when playing"
	_dev_hud_box.tooltip_text = "Play shows the developer overlay: frame times, speed, the lane " \
		+ "below the car, road users, time scale, pause and step, spawns, and a free camera."
	_dev_hud_box.toggled.connect(func(on: bool) -> void: plugin.set_setting("dev_hud", on))
	box.add_child(_dev_hud_box)
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Grid step"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	_grid_step = SpinBox.new()
	_grid_step.min_value = 0.0
	_grid_step.max_value = 10.0
	_grid_step.step = 0.25
	_grid_step.suffix = "m"
	_grid_step.tooltip_text = "The grid pieces snap to when placed; 0 for none."
	_grid_step.value_changed.connect(func(value: float) -> void:
		plugin.set_setting("grid_step", value))
	row.add_child(_grid_step)
	box.add_child(row)


func _build_dialogs() -> void:
	_name_dialog = ConfirmationDialog.new()
	var form := VBoxContainer.new()
	_name_field = LineEdit.new()
	_name_field.placeholder_text = "folder_name"
	_name_field.text_submitted.connect(func(_text: String) -> void:
		_name_dialog.hide()
		_on_name_confirmed())
	form.add_child(_name_field)
	_title_field = LineEdit.new()
	_title_field.placeholder_text = "Title"
	form.add_child(_title_field)
	_name_dialog.add_child(form)
	_name_dialog.register_text_enter(_title_field)
	_name_dialog.confirmed.connect(_on_name_confirmed)
	add_child(_name_dialog)
	_delete_dialog = ConfirmationDialog.new()
	_delete_dialog.title = "Delete map"
	_delete_dialog.ok_button_text = "Move to trash"
	_delete_dialog.confirmed.connect(_on_delete_confirmed)
	add_child(_delete_dialog)


## Updates the overlay check box to [param on].
func show_overlay_setting(on: bool) -> void:
	if _overlay_box:
		_overlay_box.set_pressed_no_signal(on)


func _commit_title() -> void:
	var road_map := plugin.edited_map()
	if road_map and _title.text != road_map.title:
		plugin.apply(MapKitTools.Edit.new().set_value(road_map, &"title", _title.text),
			"Set the map's title")


func _commit_description() -> void:
	var road_map := plugin.edited_map()
	if road_map and _description.text != road_map.description:
		plugin.apply(MapKitTools.Edit.new().set_value(road_map, &"description", _description.text),
			"Set the map's description")


func _create_map() -> void:
	var map_name := _new_name.text.strip_edges()
	if not MapKitTools.is_map_name(map_name):
		_say("Name the map with lower case letters, digits, and underscores, starting with a "
			+ "letter.")
		return
	var path := MapKitTools.create_map(map_name, map_name.capitalize())
	if path.is_empty():
		_say("Could not create %s; it may exist already." % map_name)
		return
	EditorInterface.get_resource_filesystem().scan()
	EditorInterface.open_scene_from_path(path)
	_new_name.clear()
	refresh_maps()
	_say("Created %s." % path)


func _open_map(path: String) -> void:
	if not path.is_empty():
		EditorInterface.open_scene_from_path(path)


func _play_open() -> void:
	var road_map := plugin.edited_map()
	if road_map == null:
		_say("Open a map scene first; its root needs to be a RoadMap.")
		return
	_play_map(road_map.scene_file_path)


func _play_map(path: String) -> void:
	if path.is_empty():
		_say("Select a map to play.")
		return
	plugin.play(path)


func _selected_map() -> String:
	var picked := _maps.get_selected_items() if _maps else PackedInt32Array()
	return _maps.get_item_metadata(picked[0]) if not picked.is_empty() else ""


func _on_map_clicked(index: int, at: Vector2, button: int) -> void:
	if button != MOUSE_BUTTON_RIGHT:
		return
	_maps.select(index)
	_map_menu.position = Vector2i(_maps.get_screen_position() + at)
	_map_menu.reset_size()
	_map_menu.popup()


func _on_map_menu(id: int) -> void:
	var path := _selected_map()
	match id:
		0: _open_map(path)
		1: _play_map(path)
		2: _ask_name(&"rename")
		3: _ask_name(&"duplicate")
		4: _ask_delete()
		5: EditorInterface.get_file_system_dock().navigate_to_path(path)


func _ask_name(action: StringName) -> void:
	var path := _selected_map()
	if path.is_empty():
		_say("Select a map first.")
		return
	var old := path.get_file().get_basename()
	_pending = {action = action, old = old}
	_name_dialog.title = "Rename %s" % old if action == &"rename" else "Duplicate %s" % old
	_name_dialog.ok_button_text = "Rename" if action == &"rename" else "Duplicate"
	_name_field.text = old if action == &"rename" else old + "_copy"
	_title_field.visible = action == &"duplicate"
	_title_field.text = ""
	_name_dialog.popup_centered(Vector2i(360, 0))
	_name_field.grab_focus()
	_name_field.select_all()


func _on_name_confirmed() -> void:
	var old: String = _pending.get("old", "")
	var new := _name_field.text.strip_edges()
	if old.is_empty() or new == old:
		return
	var problem := ""
	if _pending.action == &"rename":
		var was_open := _close_if_open(MapKitTools.map_path(old))
		if was_open == null:
			_say("Close %s first: it is open but not the current scene." % old)
			return
		problem = MapKitTools.rename_map(old, new)
		_after_files_changed()
		if problem.is_empty() and was_open:
			EditorInterface.open_scene_from_path(MapKitTools.map_path(new))
	else:
		problem = MapKitTools.duplicate_map(old, new, _title_field.text.strip_edges())
		_after_files_changed()
	_say(problem if not problem.is_empty() else "%s %s as %s." % [
		"Renamed" if _pending.action == &"rename" else "Duplicated", old, new])
	_pending = {}


func _ask_delete() -> void:
	var path := _selected_map()
	if path.is_empty():
		_say("Select a map first.")
		return
	var map_name := path.get_file().get_basename()
	var users := MapKitTools.map_users(path)
	if not users.is_empty():
		_say("%s is used by %s; it stays." % [map_name, ", ".join(users)])
		return
	_pending = {action = &"delete", old = map_name}
	_delete_dialog.dialog_text = "Move the map %s and its folder to the trash?" % map_name
	_delete_dialog.popup_centered()


func _on_delete_confirmed() -> void:
	var map_name: String = _pending.get("old", "")
	_pending = {}
	if _close_if_open(MapKitTools.map_path(map_name)) == null:
		_say("Close %s first: it is open but not the current scene." % map_name)
		return
	var problem := MapKitTools.delete_map(map_name)
	_after_files_changed()
	_say(problem if not problem.is_empty() else "Moved %s to the trash." % map_name)


## Closes the scene at [param path] when it is the one being edited. Returns whether it was open,
## or null when it is open in another tab, which cannot be closed from here.
func _close_if_open(path: String) -> Variant:
	if not EditorInterface.get_open_scenes().has(path):
		return false
	var root := EditorInterface.get_edited_scene_root()
	if root == null or root.scene_file_path != path:
		return null
	EditorInterface.save_scene()
	EditorInterface.close_scene()
	return true


func _after_files_changed() -> void:
	EditorInterface.get_resource_filesystem().scan()
	refresh_maps()


func _fix_everything() -> void:
	var edit := MapKitTools.Edit.new()
	var count := 0
	for problem: Dictionary in plugin.problems:
		if problem.fix != null:
			edit.merge((problem.fix as Callable).call())
			count += 1
	if plugin.apply(edit, "Fix %d map problems" % count):
		_say("Applied %d fixes." % count)


func _set_as_road() -> void:
	if not _need_map():
		return
	var edit := MapKitTools.Edit.new()
	for node in _selected():
		if node is GeometryInstance3D:
			edit.set_value(node, &"material_override", MapKitTools.ASPHALT)
	if not plugin.apply(edit, "Set as road"):
		_say("Select meshes to set as road.")


func _set_as_obstacle() -> void:
	if not _need_map():
		return
	var edit := MapKitTools.Edit.new()
	for node in _selected():
		if node is Node3D and not node is StaticBody3D and not node.has_node("Obstacle"):
			var body := MapKitTools.obstacle_body(node)
			if body:
				edit.add(node, body)
	if plugin.apply(edit, "Set as obstacle"):
		_say("Gave %d nodes a solid body." % edit.adds.size())
	else:
		_say("Select meshes without a solid body.")


func _connect_lanes() -> void:
	var road_map := _need_map()
	if road_map == null:
		return
	var lanes := _selected().filter(func(n: Node) -> bool: return n is TrafficLane)
	var edit := MapKitTools.Edit.new()
	if lanes.size() < 2:
		edit = MapKitTools.link_lanes(road_map)
	else:
		var links := MapKitTools.lane_links(lanes)
		for lane: TrafficLane in links:
			var next: Array[TrafficLane] = lane.next.duplicate()
			next.append_array(links[lane])
			edit.set_value(lane, &"next", next)
	if plugin.apply(edit, "Connect lanes"):
		_say("Linked %d lanes." % edit.sets.size())
	else:
		_say("Every lane end that meets another lane's start is linked already.")


func _snap() -> void:
	if not _need_map():
		return
	var edit := MapKitTools.Edit.new()
	var step: float = plugin.setting("grid_step", 0.5)
	for node in _selected():
		if node is Node3D:
			edit.set_value(node, &"position", MapKitTools.snapped(node.position,
				step if step > 0.0 else 0.5))
	plugin.apply(edit, "Snap to grid")


func _drive_to() -> void:
	var road_map := _need_map()
	if road_map == null:
		return
	var picked := _selected()
	var checkpoints := picked.filter(func(n: Node) -> bool: return n is Checkpoint)
	if checkpoints.is_empty():
		checkpoints = road_map.nodes().filter(func(n: Node) -> bool: return n is Checkpoint)
	if checkpoints.size() != 1:
		_say("Select one checkpoint with the cars, or place one: Palette, Traffic, Checkpoint.")
		return
	var checkpoint: Checkpoint = checkpoints[0]
	var cars := picked.filter(func(n: Node) -> bool: return not n is Checkpoint)
	var edit := MapKitTools.drive_to(road_map, cars, checkpoint)
	if plugin.apply(edit, "Drive to %s" % checkpoint.name, true):
		_say("%d road users drive to %s." % [edit.adds.size() + edit.sets.size(),
			checkpoint.name])
	else:
		_say("Select cars standing on or beside a lane that runs their way.")


func _drape() -> void:
	var road_map := _need_map()
	if road_map == null:
		return
	if Terrain.of(road_map) == null:
		_say("The map has no terrain: press Add terrain first.")
		return
	if not plugin.apply(MapKitTools.drape(road_map, _selected(), MAX_GRADE), "Drape on terrain"):
		_say("Nothing to drape: select roads, lanes, markings, or places.")


func _add_terrain() -> void:
	var road_map := _need_map()
	if road_map == null:
		return
	if not plugin.apply(MapKitTools.add_terrain(road_map), "Add terrain", true):
		_say("The map has a terrain already.")


func _next_look() -> void:
	if not _need_map():
		return
	if not plugin.apply(MapKitTools.next_look(_selected()), "Next look"):
		_say("Select cars, vans, buildings, scenery, or map assets.")


func _filter_palette(text: String) -> void:
	var query := text.strip_edges().to_lower()
	for button in _palette_buttons:
		var piece: MapKitTools.Piece = button.get_meta(&"piece")
		button.visible = query.is_empty() or piece.label.to_lower().contains(query) \
			or piece.section.to_lower().contains(query)
	var children := _palette.get_children()
	for i in range(0, children.size() - 1, 2):
		var any := children[i + 1].get_children().any(func(b: Control) -> bool: return b.visible)
		children[i].visible = any
		children[i + 1].visible = any


func _on_piece_toggled(on: bool, piece: MapKitTools.Piece) -> void:
	if on:
		if plugin.edited_map() == null:
			_say("Open a map scene first; its root needs to be a RoadMap.")
			_palette_group.get_pressed_button().set_pressed_no_signal(false)
			return
		plugin.placer.arm(piece)
	elif plugin.placer.piece == piece:
		plugin.placer.disarm()


func _on_piece_input(event: InputEvent, piece: MapKitTools.Piece) -> void:
	if event is InputEventMouseButton and event.double_click \
			and event.button_index == MOUSE_BUTTON_LEFT:
		var road_map := _need_map()
		if road_map == null:
			return
		plugin.placer.arm(piece)
		plugin.placer.place(road_map, view_centre(road_map))
		plugin.placer.disarm()


func _on_armed(piece: MapKitTools.Piece) -> void:
	for button in _palette_buttons:
		button.set_pressed_no_signal(button.get_meta(&"piece") == piece)
	if piece:
		_say("Click in the 3D view to place %s." % piece.label.to_lower())


func _select(node: Node) -> void:
	if node and is_instance_valid(node) and node.is_inside_tree():
		var selection := EditorInterface.get_selection()
		selection.clear()
		selection.add_node(node)


func _need_map() -> RoadMap:
	var road_map := plugin.edited_map()
	if road_map == null:
		_say("Open a map scene first; its root needs to be a RoadMap.")
	return road_map


func _selected() -> Array[Node]:
	return EditorInterface.get_selection().get_top_selected_nodes()


## Where the centre of the first 3D view looks onto the ground, in [param road_map]'s space; its
## origin when it does not.
func view_centre(road_map: RoadMap) -> Vector3:
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	var camera := viewport.get_camera_3d() if viewport else null
	if camera == null:
		return Vector3.ZERO
	var centre := viewport.get_visible_rect().size / 2.0
	var hit: Variant = Plane.PLANE_XZ.intersects_ray(camera.project_ray_origin(centre),
		camera.project_ray_normal(centre))
	return road_map.global_transform.affine_inverse() * (hit as Vector3) if hit != null \
		else Vector3.ZERO


func _say(text: String) -> void:
	_status.text = text
	_status_timer.start(STATUS_TIME)


## A folding section titled [param section_title] in [param column]; returns its content box.
func _section(column: VBoxContainer, section_title: String) -> VBoxContainer:
	var section := FoldableContainer.new()
	section.title = section_title
	column.add_child(section)
	_sections.append(section)
	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 6)
	section.add_child(box)
	return box


static func _note(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.modulate = Color(1, 1, 1, 0.65)
	return label


static func _button(text: String, pressed: Callable, tip := "", icon_name := &"") -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tip
	if not icon_name.is_empty():
		button.icon = _editor_icon(icon_name)
	if pressed.is_valid():
		button.pressed.connect(pressed)
	return button


static func _editor_icon(icon_name: StringName) -> Texture2D:
	var theme := EditorInterface.get_editor_theme()
	return theme.get_icon(icon_name, &"EditorIcons") if theme \
		and theme.has_icon(icon_name, &"EditorIcons") else null


static func _piece_icon(piece: MapKitTools.Piece) -> Texture2D:
	if piece.icon.begins_with("res://"):
		return load(piece.icon) as Texture2D if ResourceLoader.exists(piece.icon) \
			else _editor_icon(&"Node3D")
	return _editor_icon(StringName(piece.icon))
