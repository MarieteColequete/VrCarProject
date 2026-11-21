@tool
class_name MapKitPlacer
extends RefCounted
## Places palette pieces by clicking in the 3D view. Arming a piece shows a ghost of it that
## follows the mouse over the ground, snapped to the grid, or onto an open road end when a road or
## junction comes near one. A left click places it, Shift and click places it and keeps it armed,
## R turns it a quarter, Shift and R by 15 degrees, and Escape or a right click stops.

## Emitted when a piece is armed or disarmed.
signal armed_changed(piece: MapKitTools.Piece)

const TURN := PI / 2.0
const FINE_TURN := PI / 12.0

var plugin: MapKitPlugin
## The armed piece; null when none is.
var piece: MapKitTools.Piece

var _ghost: Node3D
var _turn := 0.0
## Where the ghost stands, in the map's space; null before the mouse has been over the ground.
var _at: Variant = null


func _init(p_plugin: MapKitPlugin) -> void:
	plugin = p_plugin


func is_armed() -> bool:
	return piece != null


## Arms [param p_piece] for placing in the open map.
func arm(p_piece: MapKitTools.Piece) -> void:
	disarm()
	var road_map := plugin.edited_map()
	if road_map == null:
		return
	piece = p_piece
	_turn = 0.0
	_at = null
	_ghost = piece.make.call()
	_ghost.visible = false
	road_map.add_child(_ghost, false, Node.INTERNAL_MODE_BACK)
	armed_changed.emit(piece)


func disarm() -> void:
	if _ghost and is_instance_valid(_ghost):
		_ghost.get_parent().remove_child(_ghost)
		_ghost.queue_free()
	_ghost = null
	var was := piece
	piece = null
	if was:
		armed_changed.emit(null)
		plugin.update_overlays()


## The line the overlay shows while a piece is armed; empty otherwise.
func hint() -> String:
	if piece == null:
		return ""
	return "Placing %s: click to place, Shift+click to keep placing, R to turn, Esc to stop" \
		% piece.label.to_lower()


## Handles [param event] over the 3D view seen by [param camera]; returns whether it used it.
func input(camera: Camera3D, event: InputEvent) -> bool:
	if piece == null:
		return false
	var road_map := plugin.edited_map()
	if road_map == null or _ghost == null or not is_instance_valid(_ghost):
		disarm()
		return false
	if event is InputEventMouseMotion:
		_follow(road_map, camera, (event as InputEventMouseMotion).position)
		return false
	if event is InputEventMouseButton and event.pressed:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_RIGHT:
			disarm()
			return true
		if button.button_index == MOUSE_BUTTON_LEFT:
			_follow(road_map, camera, button.position)
			if _at != null:
				place(road_map, _at)
			if not button.shift_pressed:
				disarm()
			return true
	if event is InputEventKey and event.pressed and not event.echo:
		var key := event as InputEventKey
		if key.keycode == KEY_ESCAPE:
			disarm()
			return true
		if key.keycode == KEY_R:
			_turn = fmod(_turn + (FINE_TURN if key.shift_pressed else TURN), TAU)
			if _at != null:
				_show_ghost(road_map, _at)
			return true
	return false


## Places the armed piece at [param point], in the map's space, with undo; joined to an open road
## end when it is a road or junction near one.
func place(road_map: RoadMap, point: Vector3) -> void:
	if piece == null:
		return
	var node: Node3D = piece.make.call()
	var parent: Node = road_map.get_node_or_null(piece.group) if not piece.group.is_empty() \
		else road_map
	if parent == null:
		parent = road_map
	node.transform = MapKitTools.to_map(parent, road_map).affine_inverse() \
		* _placement(road_map, node, point)
	plugin.apply(MapKitTools.Edit.new().add(parent, node), "Add %s" % piece.label.to_lower(), true)


## Where [param node] goes for the mouse at [param point]: on a road end it joins, or on the grid
## turned as set, its own height kept.
func _placement(road_map: RoadMap, node: Node3D, point: Vector3) -> Transform3D:
	if piece.joins_roads:
		var joined: Variant = MapKitTools.joining_transform(road_map, node, point)
		if joined != null:
			return joined
	var step: float = plugin.setting("grid_step", 0.5)
	var at := MapKitTools.snapped(point, step) + Vector3(0, node.position.y, 0)
	return Transform3D(Basis(Vector3.UP, _turn), at)


func _follow(road_map: RoadMap, camera: Camera3D, mouse: Vector2) -> void:
	var hit: Variant = Plane.PLANE_XZ.intersects_ray(camera.project_ray_origin(mouse),
		camera.project_ray_normal(mouse))
	if hit == null:
		return
	_at = road_map.global_transform.affine_inverse() * (hit as Vector3)
	_show_ghost(road_map, _at)


func _show_ghost(road_map: RoadMap, point: Vector3) -> void:
	var fresh: Node3D = piece.make.call()
	_ghost.transform = _placement(road_map, fresh, point)
	if _ghost is RoadSegment and fresh is RoadSegment:
		(_ghost as RoadSegment).curve = (fresh as RoadSegment).curve
		(_ghost as RoadSegment).lane_width = (fresh as RoadSegment).lane_width
	elif _ghost is RoadJunction and fresh is RoadJunction:
		(_ghost as RoadJunction).road_width = (fresh as RoadJunction).road_width
	fresh.free()
	_ghost.visible = true
