class_name GpsReader
extends RefCounted
## Reads the dashboard GPS's map ([GpsMap]) from a scenario as it loads: the roads from the faces of
## every mesh of asphalt (hand-drawn roads, [RoadSegment]s, [RoadJunction]s), with the grass islands
## that stand on them; the lines painted on them, the ways ([GpsRoute]) and the goals ([GoalRule]
## zones) from the [World] they were baked into.

const ASPHALT := preload("res://scenarios/kit/asphalt.tres")
const GRASS := preload("res://scenarios/kit/grass.tres")
## The least upward share of a face's normal for it to be drawn: the tops (and bottoms) of the
## road pieces, not their sides.
const FLAT := 0.7
## The lines drawn on the roads; kerbs, zebras and no-parking lines are left out.
const LINES := [RoadMarking.Kind.SOLID, RoadMarking.Kind.DASHED, RoadMarking.Kind.DOUBLE_SOLID,
	RoadMarking.Kind.STOP_LINE, RoadMarking.Kind.GIVE_WAY_LINE, RoadMarking.Kind.BAY_EDGE]


## The map of [param scenario] as baked into [param world].
static func read(scenario: Scenario, world: World) -> GpsMap:
	var map := GpsMap.new()
	_read_meshes(map, scenario)
	var markings := world.store(Schema.MARKING)
	for row in markings.size():
		if markings.column(&"kind")[row] in LINES:
			map.lines.append(GpsMap.flat(markings.column(&"points")[row]))
	for route: Dictionary in world.resources.get(Schema.ROUTES, []):
		map.routes.append({step = route.step, points = GpsMap.flat(route.points)})
	var rules := world.store(Schema.RULE)
	var zones := world.store(Schema.ZONE)
	for row in rules.size():
		var step: Callable = rules.column(&"step")[row]
		var params: Dictionary = rules.column(&"params")[row]
		if step.get_object() != GoalRule or not zones.has(params.get(&"zone", 0)):
			continue
		var at: Transform3D = zones.get_value(params.zone, &"transform")
		var half: Vector3 = zones.get_value(params.zone, &"half")
		map.goals.append({step = params.step, centre = Vector2(at.origin.x, at.origin.z),
			radius = maxf(half.x, half.z)})
	return map


static func _read_meshes(map: GpsMap, scenario: Node) -> void:
	var pieces: Array[MeshInstance3D] = []
	_meshes(scenario, pieces)
	var road_boxes: Array[Rect2] = []
	var grass: Array[MeshInstance3D] = []
	for piece in pieces:
		var road := piece.get_parent() is RoadSegment or piece.get_parent() is RoadJunction
		for s in piece.mesh.get_surface_count():
			var material := piece.get_active_material(s)
			if road or material == ASPHALT:
				_faces(piece, s, map.roads)
				road_boxes.append(_ground_box(piece))
			elif material == GRASS:
				grass.append(piece)
	for piece in grass:
		var box := _ground_box(piece)
		for road in road_boxes:
			if road.encloses(box):
				for s in piece.mesh.get_surface_count():
					_faces(piece, s, map.islands)
				break


static func _meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	for child in node.get_children(true):
		if child is MeshInstance3D and (child as MeshInstance3D).mesh \
				and (child as MeshInstance3D).is_visible_in_tree():
			out.append(child)
		_meshes(child, out)


static func _ground_box(piece: MeshInstance3D) -> Rect2:
	var box := piece.global_transform * piece.mesh.get_aabb()
	return Rect2(box.position.x, box.position.z, box.size.x, box.size.z)


static func _faces(piece: MeshInstance3D, surface: int, out: PackedVector2Array) -> void:
	var arrays := piece.mesh.surface_get_arrays(surface)
	if arrays.is_empty() or arrays[Mesh.ARRAY_VERTEX] == null:
		return
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] \
		else PackedInt32Array(range(vertices.size()))
	var at := piece.global_transform
	for i in range(0, indices.size() - 2, 3):
		var a := at * vertices[indices[i]]
		var b := at * vertices[indices[i + 1]]
		var c := at * vertices[indices[i + 2]]
		var normal := (b - a).cross(c - a)
		if normal.length_squared() < 1e-10 or absf(normal.normalized().y) < FLAT:
			continue
		out.append_array([Vector2(a.x, a.z), Vector2(b.x, b.z), Vector2(c.x, c.z)])
