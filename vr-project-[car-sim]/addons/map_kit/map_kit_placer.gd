@tool
class_name MapKitPlacer
extends RefCounted
## Places palette pieces and models by clicking in the 3D view. Arming a piece shows a ghost of it
## that follows the mouse over the ground (the map's [Terrain] where it has one), snapped to the
## grid across, or onto an open road end when a road or junction comes near one; a terrain shape
## goes under the terrain; a model stands on whatever solid is under the mouse
## (a road tile, a pavement, another model's body), or else on the ground. A model's ghost is see-through and solid to nothing. A left click
## places it, Shift and click places it and keeps it armed, R turns it a quarter, Shift and R by
## 15 degrees, Shift and E straightens it, and Escape or a right click stops. With nothing armed,
## Space arms the last piece placed again. A piece keeps its turn in [member MapKitTools.Piece.turn].

## Emitted when a piece is armed or disarmed.
signal armed_changed(piece: MapKitTools.Piece)
## Emitted when [param piece] has been placed.
signal placed(piece: MapKitTools.Piece)
## Emitted when the armed piece is turned, so its turn can be kept for next time.
signal turned(piece: MapKitTools.Piece, turn: float)

const TURN := PI / 2.0
const FINE_TURN := PI / 12.0
## How far a ray looks for a surface under the mouse, metres.
const REACH := 2000.0

var plugin: MapKitPlugin
## The armed piece; null when none is.
var piece: MapKitTools.Piece
## The piece placed last, for Space to arm again.
var last: MapKitTools.Piece

var _ghost: Node3D
## The ghost's own height above where it stands, as the piece makes it.
var _base_y := 0.0
## Where the ghost stands, in the map's space; null before the mouse has been over the map.
var _at: Variant = null
## The mouse position the ghost last followed, in the 3D view.
var _mouse := Vector2(-1.0, -1.0)
## The ray waiting for the next physics frame to find the surface under the mouse:
## [code][world, from, normal][/code]; empty when none is.
var _ray: Array = []


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
	_at = null
	_ghost = piece.make.call()
	if _ghost is MapAsset:
		(_ghost as MapAsset).preview = true
	_base_y = _ghost.position.y
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
	return "Placing %s, turned %d°: click to place, Shift+click to keep placing, R to turn, " \
		% [piece.label.to_lower(), roundi(rad_to_deg(piece.turn))] \
		+ "Shift+E to straighten, Esc to stop"


## Handles [param event] over the 3D view seen by [param camera]; returns whether it used it.
func input(camera: Camera3D, event: InputEvent) -> bool:
	var key := event as InputEventKey
	var pressed_key := key != null and key.pressed and not key.echo
	if piece == null:
		if pressed_key and key.keycode == KEY_SPACE and last and plugin.edited_map():
			arm(last)
			return true
		return false
	var road_map := plugin.edited_map()
	if road_map == null or _ghost == null or not is_instance_valid(_ghost):
		disarm()
		return false
	if event is InputEventMouseMotion:
		follow(camera, (event as InputEventMouseMotion).position)
		return false
	if event is InputEventMouseButton and event.pressed:
		var button := event as InputEventMouseButton
		if button.button_index == MOUSE_BUTTON_RIGHT:
			disarm()
			return true
		if button.button_index == MOUSE_BUTTON_LEFT:
			# Where the mouse has not moved, the ghost already stands on the surface found.
			if button.position != _mouse or _at == null:
				follow(camera, button.position)
			if _at != null:
				place(road_map, _at)
			if not button.shift_pressed:
				disarm()
			return true
	if pressed_key:
		if key.keycode == KEY_ESCAPE:
			disarm()
			return true
		if key.keycode == KEY_R or (key.keycode == KEY_E and key.shift_pressed):
			var turn := 0.0 if key.keycode == KEY_E \
				else fmod(piece.turn + (FINE_TURN if key.shift_pressed else TURN), TAU)
			piece.turn = turn
			turned.emit(piece, turn)
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
	if node is TerrainShape and Terrain.of(road_map):
		parent = Terrain.of(road_map)
	node.transform = MapKitTools.to_map(parent, road_map).affine_inverse() \
		* _placement(road_map, node, point)
	plugin.apply(MapKitTools.Edit.new().add(parent, node), "Add %s" % piece.label.to_lower(), true)
	last = piece
	placed.emit(piece)


## Places the armed piece where the ghost stands; nothing before the mouse has been over the map.
func place_here(road_map: RoadMap) -> void:
	if _at != null:
		place(road_map, _at)


## Moves the ghost to what is under [param mouse] in the view seen by [param camera]: onto the
## ground at once, and for a model onto the solid under it when the next physics frame finds one.
func follow(camera: Camera3D, mouse: Vector2) -> void:
	var road_map := plugin.edited_map()
	if road_map == null or _ghost == null or not is_instance_valid(_ghost):
		return
	_mouse = mouse
	var from := camera.project_ray_origin(mouse)
	var normal := camera.project_ray_normal(mouse)
	var into := road_map.global_transform.affine_inverse()
	var terrain := Terrain.of(road_map)
	var hit: Variant = terrain.intersect_ray(into * from, into.basis * normal, REACH) \
		if terrain else null
	if hit == null:
		hit = Plane.PLANE_XZ.intersects_ray(from, normal)
		if hit != null:
			hit = into * (hit as Vector3)
	if hit != null:
		_at = hit
		_show_ghost(road_map, _at)
	if _ghost is MapAsset and camera.get_world_3d():
		# The physics space answers queries only in a physics frame, as the physics runs on a
		# thread of its own.
		if _ray.is_empty():
			plugin.get_tree().physics_frame.connect(_find_surface, CONNECT_ONE_SHOT)
		_ray = [camera.get_world_3d(), from, normal]


## Lifts the ghost onto the solid the waiting ray meets, if any: a road tile, a pavement, or
## another model's body, the ghost's own aside.
func _find_surface() -> void:
	var ray := _ray
	_ray = []
	var road_map := plugin.edited_map()
	if ray.is_empty() or road_map == null or _ghost == null or not is_instance_valid(_ghost):
		return
	var from: Vector3 = ray[1]
	var normal: Vector3 = ray[2]
	var query := PhysicsRayQueryParameters3D.create(from, from + normal * REACH)
	query.exclude = _ghost_bodies()
	var hit := (ray[0] as World3D).direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return
	_at = road_map.global_transform.affine_inverse() * (hit.position as Vector3)
	_show_ghost(road_map, _at)
	plugin.update_overlays()


## The transform of a piece placed at [param point]: snapped to the grid of [param step] across,
## standing on the point's height plus [param height], turned [param turn] about the vertical.
static func placement(point: Vector3, step: float, turn: float, height: float) -> Transform3D:
	var at := MapKitTools.snapped(Vector3(point.x, 0, point.z), step)
	at.y = point.y + height
	return Transform3D(Basis(Vector3.UP, turn), at)


## Where [param node] goes for the mouse at [param point]: on a road end it joins, or else as
## [method placement] puts it.
func _placement(road_map: RoadMap, node: Node3D, point: Vector3) -> Transform3D:
	if piece.joins_roads:
		var joined: Variant = MapKitTools.joining_transform(road_map, node, point)
		if joined != null:
			return joined
	return placement(point, plugin.setting("grid_step", 0.5), piece.turn, _base_y)


func _show_ghost(road_map: RoadMap, point: Vector3) -> void:
	# Roads and junctions are made again, since joining a road end shapes them; anything else
	# is the same wherever it stands.
	if _ghost is RoadSegment or _ghost is RoadJunction:
		var fresh: Node3D = piece.make.call()
		_ghost.transform = _placement(road_map, fresh, point)
		if _ghost is RoadSegment:
			(_ghost as RoadSegment).curve = (fresh as RoadSegment).curve
			(_ghost as RoadSegment).lane_width = (fresh as RoadSegment).lane_width
		else:
			(_ghost as RoadJunction).road_width = (fresh as RoadJunction).road_width
		fresh.free()
	else:
		_ghost.transform = _placement(road_map, _ghost, point)
	_ghost.visible = true


## The bodies of the ghost, so the ray for the surface passes through them.
func _ghost_bodies() -> Array[RID]:
	var out: Array[RID] = []
	if _ghost and is_instance_valid(_ghost):
		_bodies_of(_ghost, out)
	return out


static func _bodies_of(node: Node, out: Array[RID]) -> void:
	if node is CollisionObject3D:
		out.append((node as CollisionObject3D).get_rid())
	for child in node.get_children(true):
		_bodies_of(child, out)
