@tool
class_name TerrainShapeGizmo
extends EditorNode3DGizmoPlugin
## The Map Kit's gizmo for a [TerrainShape]: its outline draped on the land (the full effect's ring
## or rectangle and the falloff's, a ramp's arrow up its slope), a marker from the land at its
## centre to the height it aims at, and on the selected shape handles to drag its radius, falloff,
## height, or a ramp's length and width. Sizes drag on the shape's base plane and height on an
## upright plane facing the camera, snapped to [constant STEP] metres ([constant FINE_STEP] with
## Shift held); each drag is one undo action. The work is the shape's own ([method
## TerrainShape.handles], [method TerrainShape.value_from], [method TerrainShape.outline_loops]);
## the gizmo casts the mouse's ray and draws.

const OUTLINE := Color(0.95, 0.75, 0.2)
## The outline of a shape that is not selected.
const DIM := Color(0.95, 0.75, 0.2, 0.45)
const STEP := 0.5
const FINE_STEP := 0.1

var plugin: EditorPlugin


func _init(p_plugin: EditorPlugin = null) -> void:
	plugin = p_plugin
	create_material("outline", OUTLINE, false, true)
	create_material("dim", DIM, false, true)
	create_handle_material("handles")


func _get_gizmo_name() -> String:
	return "Terrain shape"


func _has_gizmo(node: Node3D) -> bool:
	return node is TerrainShape


func _redraw(gizmo: EditorNode3DGizmo) -> void:
	gizmo.clear()
	var shape := gizmo.get_node_3d() as TerrainShape
	if shape == null:
		return
	var land := land_sampler(shape)
	var selected := EditorInterface.get_selection().get_selected_nodes().has(shape)
	var material := get_material("outline" if selected else "dim", gizmo)
	var lines := PackedVector3Array()
	for loop in TerrainShape.drape(shape.outline_loops(), land):
		for k in loop.size() - 1:
			lines.append(loop[k])
			lines.append(loop[k + 1])
	# The marker: from the land at the shape's centre (a ramp's top end) up or down to its aim.
	var foot := Vector3(0.0, 0.0, -shape.size.y / 2.0) if shape.kind == TerrainShape.Kind.RAMP \
		else Vector3.ZERO
	var ground := shape.ground_under(float(land.call(foot)))
	lines.append(Vector3(foot.x, ground, foot.z))
	lines.append(Vector3(foot.x, shape.target(ground), foot.z))
	gizmo.add_lines(lines, material)
	if not selected:
		return
	var points := PackedVector3Array()
	var ids := PackedInt32Array()
	var all := shape.handles(ground)
	for k in all.size():
		var at: Vector3 = all[k].local
		if all[k].name != TerrainShape.HEIGHT:
			at.y = float(land.call(at)) + 0.05
		points.append(at)
		ids.append(k)
	gizmo.add_handles(points, get_material("handles", gizmo), ids)


func _get_handle_name(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool) -> String:
	var shape := gizmo.get_node_3d() as TerrainShape
	return String(shape.handles()[handle_id].name).capitalize()


func _get_handle_value(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool) -> Variant:
	var shape := gizmo.get_node_3d() as TerrainShape
	return shape.handle_value(shape.handles()[handle_id].name)


func _set_handle(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool, camera: Camera3D,
		screen_pos: Vector2) -> void:
	var shape := gizmo.get_node_3d() as TerrainShape
	var land := land_sampler(shape)
	var foot := Vector3(0.0, 0.0, -shape.size.y / 2.0) if shape.kind == TerrainShape.Kind.RAMP \
		else Vector3.ZERO
	var ground := shape.ground_under(float(land.call(foot)))
	var handle: StringName = shape.handles(ground)[handle_id].name
	var placed := shape.global_transform
	var plane := Plane(placed.basis.y.normalized(), placed.origin)
	if handle == TerrainShape.HEIGHT:
		var facing := -camera.global_basis.z
		facing.y = 0.0
		if facing.length_squared() < 0.0001:
			return
		plane = Plane(facing.normalized(), placed * foot)
	var hit: Variant = plane.intersects_ray(camera.project_ray_origin(screen_pos),
		camera.project_ray_normal(screen_pos))
	if hit == null:
		return
	var value := shape.value_from(handle, placed.affine_inverse() * (hit as Vector3), ground)
	shape.set_handle_value(handle, snappedf(value,
		FINE_STEP if Input.is_key_pressed(KEY_SHIFT) else STEP))


func _commit_handle(gizmo: EditorNode3DGizmo, handle_id: int, _secondary: bool,
		restore: Variant, cancel: bool) -> void:
	var shape := gizmo.get_node_3d() as TerrainShape
	var handle: StringName = shape.handles()[handle_id].name
	var property := TerrainShape.handle_property(handle)
	var now: Variant = shape.get(property)
	shape.set_handle_value(handle, float(restore))
	var before: Variant = shape.get(property)
	if cancel or plugin == null:
		return
	var undo := plugin.get_undo_redo()
	undo.create_action("Drag terrain shape's %s" % String(handle).capitalize().to_lower())
	undo.add_do_property(shape, property, now)
	undo.add_undo_property(shape, property, before)
	undo.commit_action()


## The land's height under [param shape] in its own space, at a point of that space: the map's
## [Terrain] where it has one, else the shape's base.
static func land_sampler(shape: TerrainShape) -> Callable:
	var map := Terrain.map_of(shape)
	var terrain := Terrain.of(map)
	if terrain == null:
		return func(_point: Vector3) -> float: return 0.0
	var into := Terrain.to_space(shape, map)
	var back := into.affine_inverse()
	return func(point: Vector3) -> float:
		var at := into * point
		return (back * Vector3(at.x, terrain.height_at(at), at.z)).y
