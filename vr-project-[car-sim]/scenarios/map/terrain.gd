@tool
class_name Terrain
extends Node3D
## The land of a map that is not flat: a [HeightField] [member size] metres across, centred on the
## node, its points [member cell] metres apart. The height is the [member heightmap] (white is
## [member heightmap_height] metres), then each [TerrainShape] of the map in tree order, then the
## roads: under every [RoadSegment] and [RoadJunction] the land is cut or filled to
## [constant ROAD_SINK] below the road, across the asphalt, the pavements, and a
## [constant SHOULDER] beyond, and eased back to the land over [member road_blend]. The land is drawn
## as a mesh in chunks of [constant CHUNK] cells and is solid ground, a [HeightMapShape3D] of the
## ground [BodyType]; the map's [RoadEnvironment] then has its flat ground off. Rebuilt in the editor
## when it, a shape, or a road changes; built once when a map loads. A shape that moves or changes
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

var _field: HeightField
var _body: StaticBody3D
var _chunks: Array[MeshInstance3D] = []
var _rebuild_queued := false
## What is to be built again: everything, or only the ground in [member _dirty] (the terrain's
## space).
var _whole_dirty := false
var _dirty := Rect2()
## The ground each shape reached at the last build, by its instance id, in the terrain's space.
var _shape_areas := {}
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


## The transform from [param node]'s space to [param ancestor]'s, without needing the tree.
static func to_space(node: Node, ancestor: Node) -> Transform3D:
	var out := Transform3D.IDENTITY
	var at := node
	while at != null and at != ancestor:
		if at is Node3D:
			out = (at as Node3D).transform * out
		at = at.get_parent()
	return out


## Tells the terrain of the map [param node] (a road, a junction, or a shape) is in that it
## changed; only in the editor, since a loading map builds its terrain once, and only for nodes the
## scene saves, so a ghost the Map Kit moves under the mouse rebuilds nothing. Checked a frame
## later, once a node just added has its owner.
static func notify_changed(node: Node) -> void:
	if not Engine.is_editor_hint() or not node.is_inside_tree():
		return
	node.get_tree().process_frame.connect(func() -> void:
		if not is_instance_valid(node) or not node.is_inside_tree() or node.owner == null:
			return
		var terrain := of(map_of(node))
		if terrain == null:
			return
		if node is TerrainShape:
			terrain._shape_changed(node)
		else:
			terrain.queue_rebuild(), CONNECT_ONE_SHOT)


## Tells the terrain a shape [param shape] is leaving the tree: the ground it reached is built
## again without it. Only in the editor, and only for shapes the scene saves.
static func notify_leaving(shape: TerrainShape) -> void:
	if not Engine.is_editor_hint() or shape.owner == null or not shape.is_inside_tree():
		return
	var terrain := of(map_of(shape))
	if terrain == null or terrain == shape:
		return
	var id := shape.get_instance_id()
	if terrain._shape_areas.has(id):
		terrain.queue_rebuild_area(terrain._shape_areas[id])
		terrain._shape_areas.erase(id)
	else:
		terrain.queue_rebuild()


## The ground [param shape] reaches now, in the terrain's space.
func shape_area(shape: TerrainShape) -> Rect2:
	var map := map_of(self)
	return shape.area(to_space(self, map).affine_inverse() * to_space(shape, map))


func _shape_changed(shape: TerrainShape) -> void:
	var now := shape_area(shape)
	var id := shape.get_instance_id()
	var reached: Variant = _shape_areas.get(id)
	_shape_areas[id] = now
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
	var to_terrain := to_space(self, map).affine_inverse()
	var reach := out.rect()
	var found: Array[Node] = []
	Scenario.collect(map, found)
	for node in found:
		if node is TerrainShape and node != skip:
			var shape := node as TerrainShape
			var placed := to_terrain * to_space(shape, map)
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
	var into := to_space(self, map)
	var local := into.affine_inverse() * point
	var h := land_field.height_at(local.x, local.z)
	return (into * Vector3(local.x, h, local.z)).y


## The height of the land without the roads at [param point] in the map's space.
func land_height_at(point: Vector3, land_field: HeightField = null) -> float:
	return _sample(land_field if land_field else land(), point)


## Where the ray from [param from] along [param direction], both in the map's space, meets the land;
## null when it does not.
func intersect_ray(from: Vector3, direction: Vector3, reach := 2000.0) -> Variant:
	var into := to_space(self, map_of(self))
	var inverse := into.affine_inverse()
	var hit: Variant = field().intersect_ray(inverse * from, inverse.basis * direction, reach)
	return into * (hit as Vector3) if hit != null else null


## Cuts and fills [param out] (in the terrain's space) to the map's roads and junctions.
func stamp_roads(out: HeightField) -> void:
	var map := map_of(self)
	var to_terrain := to_space(self, map).affine_inverse()
	var weight := PackedFloat32Array()
	weight.resize(out.heights.size())
	var target := PackedFloat32Array()
	target.resize(out.heights.size())
	var found: Array[Node] = []
	Scenario.collect(map, found)
	for node in found:
		if node is RoadSegment:
			var road := node as RoadSegment
			var placed := to_terrain * to_space(road, map)
			var inner := road.width() / 2.0 + (road.pavement if road.kerbs else 0.0) + SHOULDER
			var along := road.frames()
			for i in along.size() - 1:
				_stamp_stretch(out, placed * (along[i][0] as Vector3),
					placed * (along[i + 1][0] as Vector3), inner, weight, target)
		elif node is RoadJunction:
			var junction := node as RoadJunction
			_stamp_pad(out, to_terrain * to_space(junction, map), junction, weight, target)
	for k in out.heights.size():
		if weight[k] > 0.0:
			out.heights[k] = lerpf(out.heights[k], target[k], weight[k])


func _stamp_stretch(out: HeightField, a: Vector3, b: Vector3, inner: float,
		weight: PackedFloat32Array, target: PackedFloat32Array) -> void:
	var outer := inner + road_blend
	var a2 := Vector2(a.x, a.z)
	var b2 := Vector2(b.x, b.z)
	var d := b2 - a2
	var length2 := d.length_squared()
	var area := Rect2(a2, Vector2.ZERO).expand(b2).grow(outer)
	var span := out.span(area)
	if span.is_empty():
		return
	for j in range(span[1], span[3] + 1):
		var z := out.origin.y + j * out.cell
		for i in range(span[0], span[2] + 1):
			var p := Vector2(out.origin.x + i * out.cell, z)
			var t := clampf((p - a2).dot(d) / length2, 0.0, 1.0) if length2 > 0.0 else 0.0
			var lateral := p.distance_to(a2 + d * t)
			if lateral >= outer:
				continue
			var w := 1.0 if lateral <= inner else 1.0 - smoothstep(inner, outer, lateral)
			var k := j * out.count_x + i
			if w > weight[k]:
				weight[k] = w
				target[k] = lerpf(a.y, b.y, t) - ROAD_SINK


func _stamp_pad(out: HeightField, placed: Transform3D, junction: RoadJunction,
		weight: PackedFloat32Array, target: PackedFloat32Array) -> void:
	var half := junction.road_width / 2.0
	var reach := half + junction.arm_length
	var edge := RoadKit.PAVEMENT + SHOULDER
	var outer := edge + road_blend
	var inverse := placed.affine_inverse()
	var y := placed.origin.y - ROAD_SINK
	var far := reach + outer
	var area := Rect2()
	var first := true
	for corner in [Vector3(-far, 0, -far), Vector3(far, 0, -far), Vector3(far, 0, far),
			Vector3(-far, 0, far)]:
		var at: Vector3 = placed * corner
		if first:
			area = Rect2(Vector2(at.x, at.z), Vector2.ZERO)
			first = false
		else:
			area = area.expand(Vector2(at.x, at.z))
	var span := out.span(area)
	if span.is_empty():
		return
	var north := reach if junction.shape == RoadJunction.Shape.CROSSROADS else half
	for j in range(span[1], span[3] + 1):
		for i in range(span[0], span[2] + 1):
			var local := inverse * Vector3(out.origin.x + i * out.cell, placed.origin.y,
				out.origin.y + j * out.cell)
			var across := _box_distance(local.x, local.z, reach, -half, half)
			var down := _box_distance(local.x, local.z, half, -north, reach)
			var distance := minf(across, down)
			if distance >= outer:
				continue
			var w := 1.0 if distance <= edge else 1.0 - smoothstep(edge, outer, distance)
			var k := j * out.count_x + i
			if w > weight[k]:
				weight[k] = w
				target[k] = y


## How far [param x], [param z] lies outside the box [param half_x] either side of x = 0 and from
## [param z0] to [param z1].
static func _box_distance(x: float, z: float, half_x: float, z0: float, z1: float) -> float:
	var dx := maxf(absf(x) - half_x, 0.0)
	var dz := maxf(maxf(z0 - z, z - z1), 0.0)
	return Vector2(dx, dz).length()


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
	for cj in range(maxi((j0 - 2) / CHUNK, 0), mini((j1 + 1) / CHUNK, down - 1) + 1):
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
	_shape_areas.clear()
	var found: Array[Node] = []
	Scenario.collect(map_of(self), found)
	for node in found:
		if node is TerrainShape:
			_shape_areas[node.get_instance_id()] = shape_area(node)
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
