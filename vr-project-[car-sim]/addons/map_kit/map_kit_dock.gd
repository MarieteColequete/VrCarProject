@tool
class_name MapKitDock
extends EditorDock
## The Map Kit dock. From top to bottom:
## [br]- New map: a map folder and scene in [code]res://maps/[/code] from the map base, opened.
## [br]- Maps: every map the [MapCatalogue] finds; double click to open one.
## [br]- Play map: saves the open map and drives it in free drive in the map sandbox.
## [br]- Check map: lists the open map's problems; click one to select its node.
## [br]- Selection: set the selected meshes as road, give them a solid body, link the selected
## lanes whose ends meet, or snap the selection to a half-metre grid.
## [br]- Palette: adds a road piece, lane, marking, light, sign, prop, zone, or spawn to the open
## map, under its group, where the 3D view's centre meets the ground.
## [br]Every change to the map can be undone.

const SANDBOX := "res://scenarios/debug/map_sandbox.tscn"
const PLAY_FILE := "user://map_kit_play.cfg"

var plugin: EditorPlugin

var _maps: ItemList
var _problems: ItemList
var _status: Label
var _new_name: LineEdit


func _init() -> void:
	title = "Map Kit"
	default_slot = DOCK_SLOT_RIGHT_UL
	available_layouts = DOCK_LAYOUT_VERTICAL | DOCK_LAYOUT_FLOATING
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(column)

	column.add_child(_heading("New map"))
	var row := HBoxContainer.new()
	_new_name = LineEdit.new()
	_new_name.placeholder_text = "folder_name"
	_new_name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_new_name)
	row.add_child(_button("Create", _create_map))
	column.add_child(row)

	column.add_child(_heading("Maps"))
	_maps = ItemList.new()
	_maps.custom_minimum_size.y = 100
	_maps.item_activated.connect(_open_map)
	column.add_child(_maps)
	var actions := HBoxContainer.new()
	actions.add_child(_button("Refresh", refresh_maps))
	actions.add_child(_button("Play map", _play))
	actions.add_child(_button("Check map", check_map))
	column.add_child(actions)
	_problems = ItemList.new()
	_problems.custom_minimum_size.y = 80
	_problems.item_selected.connect(_select_problem)
	column.add_child(_problems)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_status)

	column.add_child(_heading("Selection"))
	var selection := HFlowContainer.new()
	selection.add_child(_button("Set as road", _set_as_road))
	selection.add_child(_button("Set as obstacle", _set_as_obstacle))
	selection.add_child(_button("Connect lanes", _connect_lanes))
	selection.add_child(_button("Snap to grid", _snap))
	column.add_child(selection)

	var section := ""
	var flow: HFlowContainer
	for piece in MapKitTools.pieces():
		if piece.section != section:
			section = piece.section
			column.add_child(_heading(section))
			flow = HFlowContainer.new()
			column.add_child(flow)
		flow.add_child(_button(piece.label, _add_piece.bind(piece)))


func _ready() -> void:
	refresh_maps()


## Lists the maps the [MapCatalogue] finds.
func refresh_maps() -> void:
	_maps.clear()
	for entry in MapCatalogue.scan():
		var index := _maps.add_item("%s  (%s)" % [entry.title, entry.id])
		_maps.set_item_metadata(index, entry.path)


## Lists the open map's problems.
func check_map() -> void:
	_problems.clear()
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		_say("Open a map first.")
		return
	var found := MapKitTools.problems(root)
	for problem in found:
		var node: Node = problem.node
		var index := _problems.add_item("%s: %s" % [node.name, problem.message])
		_problems.set_item_metadata(index, root.get_path_to(node))
	_say("No problems found." if found.is_empty() else "%d problems." % found.size())


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


func _open_map(index: int) -> void:
	EditorInterface.open_scene_from_path(_maps.get_item_metadata(index))


func _play() -> void:
	var root := _map()
	if root == null:
		return
	EditorInterface.save_scene()
	var config := ConfigFile.new()
	config.set_value("play", "map", root.scene_file_path)
	config.save(PLAY_FILE)
	EditorInterface.play_custom_scene(SANDBOX)


func _select_problem(index: int) -> void:
	var root := EditorInterface.get_edited_scene_root()
	var node := root.get_node_or_null(_problems.get_item_metadata(index)) if root else null
	if node:
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(node)


func _add_piece(piece: MapKitTools.Piece) -> void:
	var root := _map()
	if root == null:
		return
	var parent: Node = root.get_node_or_null(piece.group) if not piece.group.is_empty() else root
	if parent == null:
		parent = root
	var node: Node3D = piece.make.call()
	var lift := node.position.y
	var at := MapKitTools.snapped(_view_centre(), 0.5)
	if parent is Node3D:
		at = (parent as Node3D).global_transform.affine_inverse() * at
	node.position = at + Vector3(0, lift, 0)
	var undo := plugin.get_undo_redo()
	undo.create_action("Add %s" % piece.label, UndoRedo.MERGE_DISABLE, root)
	undo.add_do_method(parent, &"add_child", node, true)
	undo.add_do_method(MapKitTools, &"own", node, root)
	undo.add_do_reference(node)
	undo.add_undo_method(parent, &"remove_child", node)
	undo.commit_action()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(node)


func _set_as_road() -> void:
	var root := _map()
	if root == null:
		return
	var meshes := _selected().filter(func(n: Node) -> bool: return n is GeometryInstance3D)
	if meshes.is_empty():
		_say("Select meshes to set as road.")
		return
	var undo := plugin.get_undo_redo()
	undo.create_action("Set as road", UndoRedo.MERGE_DISABLE, root)
	for mesh: GeometryInstance3D in meshes:
		undo.add_do_property(mesh, &"material_override", MapKitTools.ASPHALT)
		undo.add_undo_property(mesh, &"material_override", mesh.material_override)
	undo.commit_action()


func _set_as_obstacle() -> void:
	var root := _map()
	if root == null:
		return
	var bodies := {}
	for node in _selected():
		if node is Node3D and not node is StaticBody3D and not node.has_node("Obstacle"):
			var body := MapKitTools.obstacle_body(node)
			if body:
				bodies[node] = body
	if bodies.is_empty():
		_say("Select meshes without a solid body.")
		return
	var undo := plugin.get_undo_redo()
	undo.create_action("Set as obstacle", UndoRedo.MERGE_DISABLE, root)
	for node: Node in bodies:
		var body: StaticBody3D = bodies[node]
		undo.add_do_method(node, &"add_child", body, true)
		undo.add_do_method(MapKitTools, &"own", body, root)
		undo.add_do_reference(body)
		undo.add_undo_method(node, &"remove_child", body)
	undo.commit_action()
	_say("Gave %d nodes a solid body." % bodies.size())


func _connect_lanes() -> void:
	var root := _map()
	if root == null:
		return
	var lanes := _selected().filter(func(n: Node) -> bool: return n is TrafficLane)
	if lanes.size() < 2:
		lanes = root.nodes().filter(func(n: Node) -> bool: return n is TrafficLane)
	var links := MapKitTools.lane_links(lanes)
	if links.is_empty():
		_say("No lane ends meet another lane's start.")
		return
	var undo := plugin.get_undo_redo()
	undo.create_action("Connect lanes", UndoRedo.MERGE_DISABLE, root)
	var count := 0
	for lane: TrafficLane in links:
		var next: Array[TrafficLane] = lane.next.duplicate()
		next.append_array(links[lane])
		count += links[lane].size()
		undo.add_do_property(lane, &"next", next)
		undo.add_undo_property(lane, &"next", lane.next.duplicate())
	undo.commit_action()
	_say("Connected %d lane ends." % count)


func _snap() -> void:
	var root := _map()
	var nodes := _selected().filter(func(n: Node) -> bool: return n is Node3D)
	if root == null or nodes.is_empty():
		return
	var undo := plugin.get_undo_redo()
	undo.create_action("Snap to grid", UndoRedo.MERGE_DISABLE, root)
	for node: Node3D in nodes:
		undo.add_do_property(node, &"position", MapKitTools.snapped(node.position))
		undo.add_undo_property(node, &"position", node.position)
	undo.commit_action()


## The open scene's root when it is a map; otherwise null, with a message.
func _map() -> RoadMap:
	var root := EditorInterface.get_edited_scene_root() as RoadMap
	if root == null:
		_say("Open a map scene first; its root needs to be a RoadMap.")
	return root


func _selected() -> Array[Node]:
	return EditorInterface.get_selection().get_top_selected_nodes()


## Where the centre of the first 3D view looks onto the ground; the origin when it does not.
func _view_centre() -> Vector3:
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	var camera := viewport.get_camera_3d() if viewport else null
	if camera == null:
		return Vector3.ZERO
	var centre := viewport.get_visible_rect().size / 2.0
	var origin := camera.project_ray_origin(centre)
	var direction := camera.project_ray_normal(centre)
	var hit: Variant = Plane.PLANE_XZ.intersects_ray(origin, direction)
	return hit if hit != null else Vector3.ZERO


func _say(text: String) -> void:
	_status.text = text


static func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 15)
	return label


static func _button(text: String, pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(pressed)
	return button
