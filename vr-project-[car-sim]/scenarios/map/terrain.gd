@tool
class_name Terrain
extends Node3D
## The land of a map that is not flat: a [HeightField] [member size] metres across, centred on the
## node, its points [member cell] metres apart. The height is the [member heightmap] (white is
## [member heightmap_height] metres), then each [TerrainShape] of the map in tree order, then the
## roads: under every [RoadSegment] and [RoadJunction], and every road drawn by hand
## ([method is_drawn_road]), the land is cut or filled to [constant ROAD_SINK] below the road,
## across the asphalt, the pavements, and a [constant SHOULDER] beyond, and eased back to the land
## over [member road_blend]. The land is drawn
## as a mesh in chunks of [constant CHUNK] cells and is solid ground, a [HeightMapShape3D] of the
## ground [BodyType]; the map's [RoadEnvironment] should have its flat ground off, which Map Kit's
## Add terrain does and the terrain warns of otherwise. Rebuilt in the editor when it, a shape, or
## a road changes, moves or goes; built once when a map loads. A shape that moves or changes
## rebuilds only the ground it reached and now reaches, and only the chunks over it, and the
## collider follows a moment after the last change ([constant COLLIDER_DELAY]), so a shape
## dragged in the editor follows the mouse.

## Width (X) and length (Z) of the land, metres.
@export var size := Vector2(200, 200):
	set(value):
		size = value
		queue_rebuild()
## Metres between the grid's points.
@export_range(0.25, 8.0, 0.25) var cell := 1.0:
	set(value):
		cell = value
		queue_rebuild()
## The base of the land, stretched over the whole of it: the red channel, black low.
@export var heightmap: Texture2D:
	set(value):
		heightmap = value
		queue_rebuild()
## Metres the heightmap's white stands above its black.
@export var heightmap_height := 10.0:
	set(value):
		heightmap_height = value
		queue_rebuild()
@export var material: Material = preload("res://scenarios/kit/grass.tres"):
	set(value):
		material = value
		queue_rebuild()
## Metres over which the land eases from a road's edge back to its own height.
@export_range(0.0, 50.0, 0.5) var road_blend := 8.0:
	set(value):
		road_blend = value
		queue_rebuild()
@export_tool_button("Rebuild", "Reload") var rebuild_action := rebuild

## Cells along each side of a drawn chunk.
const CHUNK := 64
## How far under a road the land lies, so the road always covers it.
const ROAD_SINK := 0.05
## Metres of flat land beside a road's pavement.
const SHOULDER := 1.0
## Metres per repeat of the material across the land.
const UV_SCALE := 4.0
const GROUP := &"map_terrain"
## Seconds after the last change in the editor before the collider is rebuilt.
const COLLIDER_DELAY := 0.4
## The material that makes a mesh road ([method is_drawn_road]).
const ASPHALT := preload("res://scenarios/kit/asphalt.tres")

var _field: HeightField
var _body: StaticBody3D
var _chunks: Array[MeshInstance3D] = []
var _rebuild_queued := false
## What is to be built again: everything, or only the ground in [member _dirty] (the terrain's
## space).
var _whole_dirty := false
var _dirty := Rect2()
## The ground each piece that shapes the land (a shape, a road, a junction) reached at the last
## build, by its instance id, in the terrain's space.
var _areas := {}
## The nodes whose change is already to be looked at this frame, by instance id
## ([method notify_changed]).
static var _notified := {}
var _collider_wait := 0
## How many chunks the last build drew, for tests.
var chunks_drawn := 0


func _ready() -> void:
	add_to_group(GROUP)
	rebuild()


## The map's terrain: its first [Terrain]; null when it has none or [param map] is null.
static func of(map: Node) -> Terrain:
	if map == null:
		return null
	if map is Terrain:
		return map
	if map.is_inside_tree():
		for node in map.get_tree().get_nodes_in_group(GROUP):
			if map.is_ancestor_of(node):
				return node
		return null
	var found: Array[Node] = []
	Scenario.collect(map, found)
	for node in found:
		if node is Terrain:
			return node
	return null


## The map [param node] is in: its nearest [RoadMap] ancestor, else the top of its branch.
static func map_of(node: Node) -> Node:
	var at := node
	var top := node
	while at != null:
		if at is RoadMap:
			return at
		top = at
		at = at.get_parent()
	return top


## Tells the terrain of the map [param node] (a road, a junction, or a shape) is in that it
## changed; only in the editor, since a loading map builds its terrain once, and only for nodes the
## scene saves, so a ghost the Map Kit moves under the mouse rebuilds nothing. Checked a frame
## later, once a node just added has its owner.
static func notify_changed(node: Node) -> void:
	if not Engine.is_editor_hint() or not node.is_inside_tree():
		return
	# Once a frame per node, however often it moves in it.
	var id := node.get_instance_id()
	if _notified.has(id):
		return
	_notified[id] = true
	# The lambda holds the node's id, not the node: a node freed before the frame (the placer's
	# ghost, a road deleted) would be an error to pass to it.
	node.get_tree().process_frame.connect(func() -> void:
		_notified.erase(id)
		var changed := instance_from_id(id) as Node3D
		if changed == null or not changed.is_inside_tree() or changed.owner == null:
			return
		var terrain := of(map_of(changed))
		if terrain == null:
			return
		if _shapes_land(changed):
			terrain._piece_changed(changed)
		else:
			terrain.queue_rebuild(), CONNECT_ONE_SHOT)


## Tells the terrain a piece [param node] that shapes the land (a [TerrainShape], [RoadSegment] or
## [RoadJunction]) is leaving the tree: the ground it reached is built again without it. Only in
## the editor, and only for pieces the scene saves.
static func notify_leaving(node: Node3D) -> void:
	if not Engine.is_editor_hint() or node.owner == null or not node.is_inside_tree():
		return
	var terrain := of(map_of(node))
	if terrain == null or terrain == node:
		return
	var id := node.get_instance_id()
	if terrain._areas.has(id):
		terrain.queue_rebuild_area(terrain._areas[id])
		terrain._areas.erase(id)
	else:
		terrain.queue_rebuild()


## Whether [param node] is a road drawn by hand: a flat mesh with the asphalt material, as the Map
## Kit's Set as road gives it. The land lies under its whole box, along its longer side. Moving one
## in the editor does not rebuild the land; the next build follows it.
static func is_drawn_road(node: Node) -> bool:
	if not node is MeshInstance3D or (node as MeshInstance3D).mesh == null:
		return false
	var mesh := node as MeshInstance3D
	return mesh.material_override == ASPHALT or (mesh.get_surface_override_material_count() > 0
		and mesh.get_surface_override_material(0) == ASPHALT)


## The ends of a road drawn by hand, in [param placed]'s space (the mesh's placement), at the top of
## its box, and half its width across: its middle line along its longer side.
static func drawn_road_line(mesh: MeshInstance3D, placed: Transform3D) -> Array:
	var box := mesh.mesh.get_aabb()
	var middle := box.get_center()
	middle.y = box.end.y
	var along := Vector3(box.size.x / 2.0, 0, 0)
	var across := box.size.z / 2.0
	if box.size.z > box.size.x:
		along = Vector3(0, 0, box.size.z / 2.0)
		across = box.size.x / 2.0
	return [placed * (middle - along), placed * (middle + along), across]


## Whether [param node] shapes the land: a shape, a road, or a junction.
static func _shapes_land(node: Node) -> bool:
	return node is TerrainShape or node is RoadSegment or node is RoadJunction


## The ground [param shape] reaches now, in the terrain's space.
func shape_area(shape: TerrainShape) -> Rect2:
	return piece_area(shape)


## The ground [param node] (a shape, a road, or a junction) reaches now, its blend into the land
## included, in the terrain's space.
func piece_area(node: Node3D) -> Rect2:
	var map := map_of(self)
	var placed := RoadMap.to_map(self, map).affine_inverse() * RoadMap.to_map(node, map)
	if node is TerrainShape:
		return (node as TerrainShape).area(placed)
	if node is RoadSegment:
		var road := node as RoadSegment
		var reach := road.width() / 2.0 + (road.pavement if road.kerbs else 0.0) + SHOULDER \
			+ road_blend
		var out := Rect2()
		var first := true
		for frame: Array in road.frames():
			var at := placed * (frame[0] as Vector3)
			var flat := Vector2(at.x, at.z)
			out = Rect2(flat, Vector2.ZERO) if first else out.expand(flat)
			first = false
		return out.grow(reach)
	if node is RoadJunction:
		var junction := node as RoadJunction
		var far := junction.road_width / 2.0 + junction.arm_length + RoadKit.PAVEMENT \
			+ SHOULDER + road_blend
		return Rect2(Vector2(placed.origin.x, placed.origin.z), Vector2.ZERO).grow(far * sqrt(2.0))
	if is_drawn_road(node):
		var line := drawn_road_line(node as MeshInstance3D, placed)
		var a: Vector3 = line[0]
		var b: Vector3 = line[1]
		return Rect2(Vector2(a.x, a.z), Vector2.ZERO).expand(Vector2(b.x, b.z)) \
			.grow(line[2] + SHOULDER + road_blend)
	return Rect2()


func _piece_changed(node: Node3D) -> void:
	var now := piece_area(node)
	var id := node.get_instance_id()
	var reached: Variant = _areas.get(id)
	_areas[id] = now
	queue_rebuild_area(now.merge(reached) if reached != null else now)


## The land last built, roads included, in the terrain's own space; built now if it was not yet.
func field() -> HeightField:
	if _field == null:
		_field = build_field()
	return _field


## The land without the roads: the heightmap and the shapes (but [param skip]), in the terrain's
## own space.
func land(skip: TerrainShape = null) -> HeightField:
	var out := HeightField.covering(size, cell)
	_shape_land(out, out.rect(), skip)
	return out


## Adds the heightmap (stretched over [param whole], the whole land's rectangle) and the shapes
## but [param skip] to [param out], a part of the land or the whole of it.
func _shape_land(out: HeightField, whole: Rect2, skip: TerrainShape = null) -> void:
	if heightmap:
		out.add_image(heightmap.get_image(), heightmap_height, whole)
	var map := map_of(self)
	var to_terrain := RoadMap.to_map(self, map).affine_inverse()
	var reach := out.rect()
	var found: Array[Node] = []
	Scenario.collect(map, found)
	for node in found:
		if node is TerrainShape and node != skip:
			var shape := node as TerrainShape
			var placed := to_terrain * RoadMap.to_map(shape, map)
			if shape.area(placed).intersects(reach, true):
				shape.apply(out, placed)


## The land with the roads cut and filled into it, in the terrain's own space.
func build_field() -> HeightField:
	var out := land()
	stamp_roads(out)
	return out


## The height of the land at [param point] (x, z) in the map's space, roads included; in the map's
## space too.
func height_at(point: Vector3) -> float:
	return _sample(field(), point)


## The height of [param land] (in the terrain's space) at [param point] in the map's space.
func _sample(land_field: HeightField, point: Vector3) -> float:
	var map := map_of(self)
	var into := RoadMap.to_map(self, map)
	var local := into.affine_inverse() * point
	var h := land_field.height_at(local.x, local.z)
	return (into * Vector3(local.x, h, local.z)).y


## The height of the land without the roads at [param point] in the map's space.
func land_height_at(point: Vector3, land_field: HeightField = null) -> float:
	return _sample(land_field if land_field else land(), point)


## Where the ray from [param from] along [param direction], both in the map's space, meets the land;
## null when it does not.
func intersect_ray(from: Vector3, direction: Vector3, reach := 2000.0) -> Variant:
	var into := RoadMap.to_map(self, map_of(self))
	var inverse := into.affine_inverse()
	var hit: Variant = field().intersect_ray(inverse * from, inverse.basis * direction, reach)
	if hit == null:
		return null
	return into * (hit as Vector3)


## Cuts and fills [param out] (in the terrain's space) to the map's roads, junctions, and roads
## drawn by hand.
func stamp_roads(out: HeightField) -> void:
	var map := map_of(self)
	var to_terrain := RoadMap.to_map(self, map).affine_inverse()
	var weight := PackedFloat32Array()
	weight.resize(out.heights.size())
	var target := PackedFloat32Array()
	target.resize(out.heights.size())
	# How far each point is from the piece it takes its height from: of two pieces that hold it
	# as firmly, the nearer one sets it.
	var near := PackedFloat32Array()
	near.resize(out.heights.size())
	near.fill(INF)
	var reach := out.rect()
	var found: Array[Node] = []
	Scenario.collect(map, found)
	for node in found:
		# A road known from the last build to lie away from this part of the land is not drawn.
		var known: Variant = _areas.get(node.get_instance_id())
		if known != null and not (known as Rect2).intersects(reach, true):
			continue
		if node is RoadSegment:
			var road := node as RoadSegment
			var placed := to_terrain * RoadMap.to_map(road, map)
			var inner := road.width() / 2.0 + (road.pavement if road.kerbs else 0.0) + SHOULDER
			var along := road.frames()
			for i in along.size() - 1:
				_stamp_stretch(out, placed * (along[i][0] as Vector3),
					placed * (along[i + 1][0] as Vector3), inner, weight, target, near)
		elif node is RoadJunction:
			var junction := node as RoadJunction
			_stamp_pad(out, to_terrain * RoadMap.to_map(junction, map), junction, weight, target,
				near)
		elif is_drawn_road(node):
			var line := drawn_road_line(node as MeshInstance3D,
				to_terrain * RoadMap.to_map(node as Node3D, map))
			_stamp_stretch(out, line[0], line[1], line[2] + SHOULDER, weight, target, near)
	for k in out.heights.size():
		if weight[k] > 0.0:
			out.heights[k] = lerpf(out.heights[k], target[k], weight[k])


## Stamps the road between [param a] and [param b]. A point beyond the stretch's ends is as far as
## the nearer end, so the stretches either side of a bend both reach it; the nearest sets its
## height, or on a slope the land would take the height of road metres up or down it.
func _stamp_stretch(out: HeightField, a: Vector3, b: Vector3, inner: float,
		weight: PackedFloat32Array, target: PackedFloat32Array, near: PackedFloat32Array) -> void:
	var outer := inner + road_blend
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var d := b2 - a2
	var area := Rect2(a2, Vector2.ZERO).expand(b2).grow(outer)
	var span := out.span(area)
	if span.is_empty():
		return
	for j in range(span[1], span[3] + 1):
		var z := out.origin.y + j * out.cell
		for i in range(span[0], span[2] + 1):
			var p := Vector2(out.origin.x + i * out.cell, z)
			var t := Geo.along_segment(p, a2, d)
			var lateral := p.distance_to(a2 + d * t)
			if lateral >= outer:
				continue
			var w := Geo.ease_out(inner, outer, lateral)
			var k := j * out.count_x + i
			if w > weight[k] or (w == weight[k] and lateral < near[k]):
				weight[k] = w
				near[k] = lateral
				target[k] = lerpf(a.y, b.y, t) - ROAD_SINK


func _stamp_pad(out: HeightField, placed: Transform3D, junction: RoadJunction,
		weight: PackedFloat32Array, target: PackedFloat32Array, near: PackedFloat32Array) -> void:
	var reach := junction.road_width / 2.0 + junction.arm_length
	var edge := RoadKit.PAVEMENT + SHOULDER
	var outer := edge + road_blend
	var inverse := placed.affine_inverse()
	var y := placed.origin.y - ROAD_SINK
	var far := reach + outer
	var span := out.span(Geo.ground_area(placed, Vector2(far, far)))
	if span.is_empty():
		return
	for j in range(span[1], span[3] + 1):
		for i in range(span[0], span[2] + 1):
			var local := inverse * Vector3(out.origin.x + i * out.cell, placed.origin.y,
				out.origin.y + j * out.cell)
			var distance := junction.distance_outside(local)
			if distance >= outer:
				continue
			var w := Geo.ease_out(edge, outer, distance)
			var k := j * out.count_x + i
			if w > weight[k] or (w == weight[k] and distance < near[k]):
				weight[k] = w
				near[k] = distance
				target[k] = y



## Builds the whole land again, once, after this frame.
func queue_rebuild() -> void:
	_whole_dirty = true
	_queue()


## Builds the land in [param area] (x, z, the terrain's space) again, once, after this frame.
func queue_rebuild_area(area: Rect2) -> void:
	_dirty = _dirty.merge(area) if _dirty.has_area() else area
	_queue()


func _queue() -> void:
	if _rebuild_queued or not is_inside_tree():
		return
	_rebuild_queued = true
	_rebuild_dirty.call_deferred()


func _rebuild_dirty() -> void:
	if _whole_dirty or _field == null:
		rebuild()
	else:
		rebuild_area(_dirty)
	_dirty = Rect2()
	# The shapes' outlines lie on the land, which moved.
	var found: Array[Node] = []
	Scenario.collect(map_of(self), found)
	for node in found:
		if node is TerrainShape:
			(node as Node3D).update_gizmos()


## Builds the land in [param area] (x, z, the terrain's space) again: its heights there from the
## heightmap, the shapes and the roads, and the chunks drawn over it. The collider follows
## [constant COLLIDER_DELAY] seconds after the last change in the editor, at once elsewhere.
func rebuild_area(area: Rect2) -> void:
	_rebuild_queued = false
	if not is_inside_tree():
		return
	if _field == null:
		rebuild()
		return
	var span := _field.span(area.grow(_field.cell))
	if span.is_empty():
		return
	var i1 := mini(maxi(span[2], span[0] + 1), _field.count_x - 1)
	var j1 := mini(maxi(span[3], span[1] + 1), _field.count_z - 1)
	var i0 := mini(span[0], i1 - 1)
	var j0 := mini(span[1], j1 - 1)
	var part := HeightField.new(_field.origin + Vector2(i0, j0) * _field.cell, _field.cell,
		i1 - i0 + 1, j1 - j0 + 1)
	_shape_land(part, _field.rect())
	stamp_roads(part)
	_field.paste(part, i0, j0)
	# A point's normal reads its neighbours, so the chunks one point beyond change too; a chunk
	# shares its edge points with the next.
	var across := ceili(float(_field.count_x - 1) / CHUNK)
	var down := ceili(float(_field.count_z - 1) / CHUNK)
	chunks_drawn = 0
	@warning_ignore("integer_division")
	for cj in range(maxi((j0 - 2) / CHUNK, 0), mini((j1 + 1) / CHUNK, down - 1) + 1):
		@warning_ignore("integer_division")
		for ci in range(maxi((i0 - 2) / CHUNK, 0), mini((i1 + 1) / CHUNK, across - 1) + 1):
			var k := cj * across + ci
			if k < _chunks.size() and is_instance_valid(_chunks[k]):
				_chunks[k].mesh = _chunk(_field, ci * CHUNK, cj * CHUNK,
					mini(CHUNK, _field.count_x - 1 - ci * CHUNK),
					mini(CHUNK, _field.count_z - 1 - cj * CHUNK), material)
				chunks_drawn += 1
	if Engine.is_editor_hint() and is_inside_tree():
		_collider_wait += 1
		var wait := _collider_wait
		get_tree().create_timer(COLLIDER_DELAY).timeout.connect(func() -> void:
			if wait == _collider_wait and is_inside_tree():
				_rebuild_collider())
	else:
		_rebuild_collider()


func _rebuild_collider() -> void:
	if _body and is_instance_valid(_body):
		remove_child(_body)
		_body.queue_free()
	_body = body(_field)
	add_child(_body, false, INTERNAL_MODE_BACK)


## Builds the land again: its field, its drawn chunks, and its collider.
func rebuild() -> void:
	_rebuild_queued = false
	_whole_dirty = false
	if not is_inside_tree():
		return
	_field = build_field()
	_areas.clear()
	var found: Array[Node] = []
	Scenario.collect(map_of(self), found)
	for node in found:
		if _shapes_land(node):
			_areas[node.get_instance_id()] = piece_area(node)
	for chunk in _chunks:
		if is_instance_valid(chunk):
			remove_child(chunk)
			chunk.queue_free()
	_chunks.clear()
	for mesh in meshes(_field, material):
		var chunk := MeshInstance3D.new()
		chunk.mesh = mesh
		add_child(chunk, false, INTERNAL_MODE_BACK)
		_chunks.append(chunk)
	chunks_drawn = _chunks.size()
	_collider_wait += 1
	_rebuild_collider()
	update_configuration_warnings()


## The land's solid body, of the ground [BodyType].
func ground_body() -> StaticBody3D:
	return _body


## The drawn chunks of [param land_field], [constant CHUNK] cells a side, with normals, in
## [param surface].
static func meshes(land_field: HeightField, surface: Material) -> Array[ArrayMesh]:
	var out: Array[ArrayMesh] = []
	var cells_x := land_field.count_x - 1
	var cells_z := land_field.count_z - 1
	for cj in range(0, cells_z, CHUNK):
		for ci in range(0, cells_x, CHUNK):
			out.append(_chunk(land_field, ci, cj, mini(CHUNK, cells_x - ci),
				mini(CHUNK, cells_z - cj), surface))
	return out


static func _chunk(land_field: HeightField, ci: int, cj: int, nx: int, nz: int,
		surface: Material) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for j in nz + 1:
		for i in nx + 1:
			var p := land_field.point(ci + i, cj + j)
			vertices.append(p)
			normals.append(land_field.point_normal(ci + i, cj + j))
			uvs.append(Vector2(p.x, p.z) / UV_SCALE)
	var row := nx + 1
	for j in nz:
		for i in nx:
			var a := j * row + i
			indices.append_array([a, a + 1, a + row, a + 1, a + row + 1, a + row])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	if surface:
		mesh.surface_set_material(0, surface)
	return mesh


## The solid ground of [param land_field]: a [HeightMapShape3D] scaled by the cell, as Jolt takes
## only uniform scales, so its heights are in cells.
static func body(land_field: HeightField) -> StaticBody3D:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	BodyType.of(&"ground").apply(ground)
	var shape := HeightMapShape3D.new()
	shape.map_width = land_field.count_x
	shape.map_depth = land_field.count_z
	var data := PackedFloat32Array()
	data.resize(land_field.heights.size())
	for k in data.size():
		data[k] = land_field.heights[k] / land_field.cell
	shape.map_data = data
	var holder := CollisionShape3D.new()
	holder.shape = shape
	var centre := land_field.rect().get_center()
	holder.transform = Transform3D(Basis.from_scale(Vector3.ONE * land_field.cell),
		Vector3(centre.x, 0.0, centre.y))
	ground.add_child(holder)
	return ground


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var found: Array[Node] = []
	Scenario.collect(map_of(self), found)
	for node in found:
		if node is RoadEnvironment and (node as RoadEnvironment).ground:
			warnings.append("Turn off the ground of %s: the terrain is the ground." % node.name)
	return warnings
