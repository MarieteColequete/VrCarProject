@tool
class_name MapKitPlugin
extends EditorPlugin
## The Map Kit: a dock for building maps in the editor, an Asset Library pane of every model in
## [code]res://assets/[/code], placing pieces and models by clicking in the 3D view, and an
## overlay drawn over it. The plugin wires the editor to the parts: the [MapKitDock] lays
## out the controls, the [MapKitPlacer] places pieces, the [MapKitOverlay] draws, and
## [MapKitTools] does the work. It applies every change to the open map as one undo action, keeps
## the open map's problems current as it is edited, and keeps the kit's settings per project.

const ICON := preload("res://addons/map_kit/icons/map_kit.svg")
const OVERLAY_ICON := preload("res://addons/map_kit/icons/overlay.svg")
## Seconds after the last edit before the problems are listed again.
const CHECK_DELAY := 0.5

## Emitted when the open map's problems have been listed again.
signal problems_changed(problems: Array[Dictionary])

var dock: MapKitDock
## The Asset Library pane.
var library: AssetLibraryDock
var placer: MapKitPlacer
## Renders the Asset Library's thumbnails.
var thumbnails: AssetThumbnails
var overlay: MapKitOverlay
## The terrain shapes' outlines on the land and their handles.
var shape_gizmo: TerrainShapeGizmo
## The open map's problems, as [method MapProblems.problems] lists them.
var problems: Array[Dictionary] = []

var _check_timer: Timer
var _drop_targets: Array[AssetDropTarget] = []
## The piece the drag being made armed, so a drag ending outside the 3D view disarms it.
var _dragged: MapKitTools.Piece
var _overlay_button: Button


func _enter_tree() -> void:
	placer = MapKitPlacer.new(self)
	thumbnails = AssetThumbnails.new()
	add_child(thumbnails)
	overlay = MapKitOverlay.new()
	shape_gizmo = TerrainShapeGizmo.new(self)
	add_node_3d_gizmo_plugin(shape_gizmo)
	dock = MapKitDock.new()
	dock.plugin = self
	add_dock(dock)
	library = AssetLibraryDock.new()
	library.plugin = self
	add_dock(library)
	_check_timer = Timer.new()
	_check_timer.one_shot = true
	_check_timer.wait_time = CHECK_DELAY
	_check_timer.timeout.connect(check_now)
	add_child(_check_timer)
	_overlay_button = Button.new()
	_overlay_button.flat = true
	_overlay_button.toggle_mode = true
	_overlay_button.icon = OVERLAY_ICON
	_overlay_button.tooltip_text = "Map Kit overlay: lane arrows, links, road ends, and spawns."
	_overlay_button.button_pressed = setting("overlay", true)
	_overlay_button.toggled.connect(set_overlay)
	add_control_to_container(CONTAINER_SPATIAL_EDITOR_MENU, _overlay_button)
	set_input_event_forwarding_always_enabled()
	set_force_draw_over_forwarding_enabled()
	scene_changed.connect(_on_scene_changed)
	get_undo_redo().history_changed.connect(queue_check)
	EditorInterface.get_inspector().property_edited.connect(_on_property_edited)
	queue_check()


func _exit_tree() -> void:
	end_asset_drag()
	placer.disarm()
	if get_undo_redo().history_changed.is_connected(queue_check):
		get_undo_redo().history_changed.disconnect(queue_check)
	var inspector := EditorInterface.get_inspector()
	if inspector.property_edited.is_connected(_on_property_edited):
		inspector.property_edited.disconnect(_on_property_edited)
	remove_node_3d_gizmo_plugin(shape_gizmo)
	shape_gizmo = null
	remove_control_from_container(CONTAINER_SPATIAL_EDITOR_MENU, _overlay_button)
	_overlay_button.queue_free()
	remove_dock(library)
	library.queue_free()
	library = null
	remove_dock(dock)
	dock.queue_free()
	dock = null


func _get_plugin_name() -> String:
	return "Map Kit"


func _get_plugin_icon() -> Texture2D:
	return ICON


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if placer.input(camera, event):
		update_overlays()
		return AFTER_GUI_INPUT_STOP
	return AFTER_GUI_INPUT_PASS


func _forward_3d_force_draw_over_viewport(viewport_control: Control) -> void:
	var road_map := edited_map()
	if road_map == null and not placer.is_armed():
		return
	var camera := EditorInterface.get_editor_viewport_3d(0).get_camera_3d()
	if camera == null:
		return
	overlay.draw(viewport_control, camera, road_map if setting("overlay", true) else null,
		problems, placer.hint())


## Arms [param piece], dragged from the Asset Library, and lays a drop target over each 3D view
## shown, until [method end_asset_drag].
func begin_asset_drag(piece: MapKitTools.Piece) -> void:
	end_asset_drag()
	if edited_map() == null:
		return
	placer.arm(piece)
	_dragged = piece
	for i in 4:
		var viewport := EditorInterface.get_editor_viewport_3d(i)
		var container := viewport.get_parent() as Control if viewport else null
		if container == null or not container.is_visible_in_tree():
			continue
		var target := AssetDropTarget.new(self, viewport)
		container.get_parent().add_child(target)
		target.cover(container)
		_drop_targets.append(target)


## Removes the drop targets, and disarms the dragged piece if it was not dropped.
func end_asset_drag() -> void:
	for target in _drop_targets:
		if is_instance_valid(target):
			target.get_parent().remove_child(target)
			target.queue_free()
	_drop_targets.clear()
	if _dragged and placer.piece == _dragged:
		placer.disarm()
	_dragged = null


## The open scene's root when it is a map; null otherwise.
func edited_map() -> RoadMap:
	return EditorInterface.get_edited_scene_root() as RoadMap


## The kit's setting [param key] for this project, or [param default].
func setting(key: String, default: Variant) -> Variant:
	return EditorInterface.get_editor_settings().get_project_metadata("map_kit", key, default)


func set_setting(key: String, value: Variant) -> void:
	EditorInterface.get_editor_settings().set_project_metadata("map_kit", key, value)


## Shows or hides the overlay over the 3D view.
func set_overlay(on: bool) -> void:
	set_setting("overlay", on)
	if _overlay_button.button_pressed != on:
		_overlay_button.set_pressed_no_signal(on)
	if dock:
		dock.show_overlay_setting(on)
	update_overlays()


## Makes [param edit] on the open map as one undo action named [param action]; the nodes it adds
## are selected when [param select]. With [param merge], a run of the same action (a slider
## dragged) merges into one. Returns whether anything changed.
func apply(edit: MapKitTools.Edit, action: String, select := false, merge := false) -> bool:
	var root := EditorInterface.get_edited_scene_root()
	if edit == null or edit.is_empty() or root == null:
		return false
	var undo := get_undo_redo()
	undo.create_action(action, UndoRedo.MERGE_ENDS if merge else UndoRedo.MERGE_DISABLE, root)
	for node in edit.removes:
		undo.add_do_method(node.get_parent(), &"remove_child", node)
	for pair: Array in edit.adds:
		undo.add_do_method(pair[0], &"add_child", pair[1], true)
		undo.add_do_method(MapKitTools, &"own", pair[1], root)
		undo.add_do_reference(pair[1])
	for triple: Array in edit.sets:
		undo.add_do_property(triple[0], triple[1], triple[2])
	# Undone in reverse: what was set, then what was added, then what was removed, so restored
	# nodes get their own names back.
	for triple: Array in edit.sets:
		undo.add_undo_property(triple[0], triple[1], (triple[0] as Object).get(triple[1]))
	for pair: Array in edit.adds:
		undo.add_undo_method(pair[0], &"remove_child", pair[1])
	for node in edit.removes:
		var parent := node.get_parent()
		undo.add_undo_method(parent, &"add_child", node, true)
		undo.add_undo_method(parent, &"move_child", node, node.get_index())
		undo.add_undo_method(MapKitTools, &"own", node, root)
		undo.add_undo_reference(node)
	undo.commit_action()
	if select and not edit.adds.is_empty():
		var selection := EditorInterface.get_selection()
		selection.clear()
		for node in edit.added():
			selection.add_node(node)
	return true


## Lists the open map's problems again after [constant CHECK_DELAY] seconds of quiet.
func queue_check() -> void:
	if _check_timer and _check_timer.is_inside_tree():
		_check_timer.start()


## Lists the open map's problems now.
func check_now() -> void:
	var road_map := edited_map()
	problems.clear()
	if road_map:
		problems = MapProblems.problems(road_map)
	overlay.refresh(road_map)
	problems_changed.emit(problems)
	update_overlays()


## Saves the open map, or opens nothing, and drives the map at [param path] in the map sandbox,
## with the Dev HUD when it is switched on.
func play(path: String) -> void:
	var root := EditorInterface.get_edited_scene_root()
	if root and root.scene_file_path == path:
		EditorInterface.save_scene()
	var config := ConfigFile.new()
	config.set_value("play", "map", path)
	config.set_value("play", "dev_hud", setting("dev_hud", false))
	config.save(MapSandbox.PLAY_FILE)
	EditorInterface.play_custom_scene(MapKitDock.SANDBOX)


func _on_scene_changed(_root: Node) -> void:
	placer.disarm()
	if dock:
		dock.show_open_map()
	check_now()


func _on_property_edited(_property: String) -> void:
	queue_check()
	if dock:
		dock.show_open_map()
