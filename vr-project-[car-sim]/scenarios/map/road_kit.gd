@tool
class_name RoadKit
extends RefCounted
## The look of the Map Kit's roads, from Kenney's City Kit (Roads): the kit's straight road tile is
## a cross-section (asphalt, a darker band by the kerb, the kerb, and the pavement) swept along a
## [RoadSegment]'s curve, and its crossroads and T tiles are stretched over a [RoadJunction]'s pad.
## The tiles are fitted, not scaled: the asphalt spans the road's own width, the band and the
## pavement keep their widths in metres, and the kerb stands [constant RoadMarking.KERB_HEIGHT]
## high, so the road matches the lanes and the kerb lines that are judged. The kit's centre line
## is painted over with asphalt: the road's [RoadMarking]s draw the lines. The pavements are
## solid: [method pavement_shapes] and [method pad_shapes] give their colliders, kerb high, for one
## body of the pavement [BodyType] per road, which stops the car's tyres at the kerb. The asphalt is
## solid too: [method surface_shapes] and [method pad_surface_shapes] give thin colliders whose
## top is the drawn asphalt, [constant LIFT] above the ground, for one body of the asphalt
## [BodyType] per road, so a wheel reads the road's grip, not the grass's. Built on the main
## thread.

const FOLDER := "res://assets/kenney/city_kit_roads/"
const STRAIGHT := FOLDER + "road-straight.glb"
const CROSSROADS := FOLDER + "road-crossroad.glb"
## The T tile: closed on its -Z side, as a T junction has no north arm.
const T := FOLDER + "road-intersection.glb"

## The darker band of asphalt along the kerb, metres.
const BAND := 0.35
## The pavement's width beyond the kerb, metres, unless a road sets its own.
const PAVEMENT := 2.0
## Height of the asphalt above the ground, as the roads drew it before.
const LIFT := 0.01
## How far a pavement's collider reaches below the ground, so nothing slips under it.
const SINK := 0.05

## In tile units: where the lane asphalt ends, where the band ends at the kerb, and the heights of
## the asphalt and of the pavement.
const _LANES := 0.3
const _KERB := 0.4
const _ROAD_Y := 0.01
const _TOP_Y := 0.02
## How close to a tile unit value counts as on it.
const _EPS := 0.002

## Tile path to its triangles in tile units: [code][positions, normals, uvs, material][/code].
static var _tiles := {}


## Forgets the tiles read, so a changed kit is read again.
static func forget() -> void:
	_tiles.clear()


## Whether the kit's road tiles load.
static func available() -> bool:
	return not _tile(STRAIGHT).is_empty()


## The road along [param frames] ([code][position, right][/code] pairs, as
## [method RoadSegment.frames] gives them), [param half] metres of asphalt either side of the
## centre, with a kerb and [param pavement] metres of pavement beyond it, or the asphalt alone when
## [param kerbs] is false. Null when the kit does not load or there are fewer than two frames.
static func road(frames: Array, half: float, pavement := PAVEMENT, kerbs := true) -> ArrayMesh:
	var tile := _tile(STRAIGHT)
	if tile.is_empty() or frames.size() < 2:
		return null
	var st := _begin(tile)
	for i in frames.size() - 1:
		_sweep(st, tile, frames[i], frames[i + 1], half, pavement, kerbs)
	return st.commit()


## A junction's pad, [param half] metres of asphalt either side of its centre on both axes: the
## crossroads tile or, for [param t], the T tile, with pavement corners [param pavement] metres
## square, and each arm of [param arms] (outward directions) reaching [param arm_length] metres
## beyond the square. Arms shorter than the pavement keep the corners whole: the road joining
## them covers the rest.
static func pad(t: bool, half: float, pavement: float, arms: Array, arm_length: float) -> ArrayMesh:
	var tile := _tile(T if t else CROSSROADS)
	var straight := _tile(STRAIGHT)
	if tile.is_empty() or straight.is_empty():
		return null
	var st := _begin(tile)
	var positions: PackedVector3Array = tile[0]
	var normals: PackedVector3Array = tile[1]
	var uvs: PackedVector2Array = tile[2]
	var short := arm_length < pavement
	for i in range(0, positions.size(), 3):
		if short and _arm_asphalt(positions, i):
			continue
		for k in 3:
			var p := positions[i + k]
			st.set_normal(normals[i + k])
			st.set_uv(uvs[i + k])
			st.add_vertex(Vector3(_across(p.x, half, pavement), _height(p.y),
				_across(p.z, half, pavement)))
	var from := half if short else half + pavement
	var reach := half + arm_length
	if reach - from > 0.01:
		for out: Vector3 in arms:
			var right := out.cross(Vector3.UP)
			# Short arms: the asphalt alone, between the corners.
			_sweep(st, straight, [out * from, right], [out * reach, right], half, pavement,
				not short)
	return st.commit()


## Whether the triangle from [param i] of a junction tile is asphalt of an arm, beyond the square.
static func _arm_asphalt(positions: PackedVector3Array, i: int) -> bool:
	var beyond := false
	for k in 3:
		var p := positions[i + k]
		if p.y > _ROAD_Y + _EPS:
			return false
		if absf(p.x) > _KERB + _EPS or absf(p.z) > _KERB + _EPS:
			beyond = true
	return beyond


## The pavements' colliders along [param frames] (as for [method road]): on each side, one prism
## per stretch between frames, from the kerb [param half] metres out to the pavement's edge, kerb
## high, so they follow the curve with no gaps. Local to the road.
static func pavement_shapes(frames: Array, half: float, pavement := PAVEMENT) -> Array[Shape3D]:
	var out: Array[Shape3D] = []
	for i in frames.size() - 1:
		var a: Array = frames[i]
		var b: Array = frames[i + 1]
		for side in [1.0, -1.0]:
			out.append(prism([a[0] + a[1] * half * side, a[0] + a[1] * (half + pavement) * side,
				b[0] + b[1] * (half + pavement) * side, b[0] + b[1] * half * side]))
	return out


## A junction pad's pavement colliders, matching [method pad]: a square at each corner between
## two arms, a strip along a T's closed (-Z) side, and the pavements of arms reaching beyond the
## corners.
static func pad_shapes(t: bool, half: float, pavement: float, arms: Array,
		arm_length: float) -> Array[Shape3D]:
	var out: Array[Shape3D] = []
	var near := half
	var far := half + pavement
	for sz in [-1.0, 1.0]:
		if t and sz < 0.0:
			out.append(prism([Vector3(-far, 0, -far), Vector3(far, 0, -far),
				Vector3(far, 0, -near), Vector3(-far, 0, -near)]))
			continue
		for sx in [-1.0, 1.0]:
			out.append(prism([Vector3(near * sx, 0, near * sz), Vector3(far * sx, 0, near * sz),
				Vector3(far * sx, 0, far * sz), Vector3(near * sx, 0, far * sz)]))
	var reach := half + arm_length
	if reach - far > 0.01:
		for out_dir: Vector3 in arms:
			var right := out_dir.cross(Vector3.UP)
			out.append_array(pavement_shapes([[out_dir * far, right], [out_dir * reach, right]],
				half, pavement))
	return out


## The asphalt's colliders along [param frames] (as for [method road]): one slab per stretch
## between frames, [param half] metres either side of the centre, its top the drawn asphalt, so
## they follow the curve with no gaps and meet the pavements at the kerb. Local to the road.
static func surface_shapes(frames: Array, half: float) -> Array[Shape3D]:
	var out: Array[Shape3D] = []
	for i in frames.size() - 1:
		var a: Array = frames[i]
		var b: Array = frames[i + 1]
		out.append(prism([a[0] - a[1] * half, a[0] + a[1] * half, b[0] + b[1] * half,
			b[0] - b[1] * half], LIFT))
	return out


## A junction pad's asphalt colliders, matching [method pad] and the plain pad alike: the square
## [param half] metres either side of the centre, and each arm of [param arms] (outward
## directions) reaching [param arm_length] metres beyond it, the asphalt's width.
static func pad_surface_shapes(half: float, arms: Array, arm_length: float) -> Array[Shape3D]:
	var out: Array[Shape3D] = []
	out.append(prism([Vector3(-half, 0, -half), Vector3(half, 0, -half), Vector3(half, 0, half),
		Vector3(-half, 0, half)], LIFT))
	if arm_length > 0.01:
		for out_dir: Vector3 in arms:
			var right := out_dir.cross(Vector3.UP)
			out.append_array(surface_shapes([[out_dir * half, right],
				[out_dir * (half + arm_length), right]], half))
	return out


## A collider standing on the ground outline [param corners] (local points, in order round it),
## from just below the ground to [param top] above it, kerb high unless given.
static func prism(corners: Array, top := RoadMarking.KERB_HEIGHT) -> ConvexPolygonShape3D:
	var points := PackedVector3Array()
	for corner: Vector3 in corners:
		points.append(Vector3(corner.x, corner.y - SINK, corner.z))
		points.append(Vector3(corner.x, corner.y + top, corner.z))
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	return shape


## One static body of the pavement [BodyType] holding [param shapes]; null when there are none.
static func pavement_body(shapes: Array[Shape3D]) -> StaticBody3D:
	return body_of(&"pavement", "Pavement", shapes)


## One static body of the asphalt [BodyType] holding [param shapes]; null when there are none.
static func surface_body(shapes: Array[Shape3D]) -> StaticBody3D:
	return body_of(&"asphalt", "Asphalt", shapes)


## One static body named [param body_name] of the [BodyType] [param kind] holding
## [param shapes]; null when there are none.
static func body_of(kind: StringName, body_name: String, shapes: Array[Shape3D]) -> StaticBody3D:
	if shapes.is_empty():
		return null
	var body := StaticBody3D.new()
	body.name = body_name
	BodyType.of(kind).apply(body)
	for shape in shapes:
		var holder := CollisionShape3D.new()
		holder.shape = shape
		body.add_child(holder)
	return body


## Where a tile's cross-section coordinate [param c] lies, metres from the centre: the lane
## asphalt stretched to the road, then the band, then the pavement.
static func _across(c: float, half: float, pavement: float) -> float:
	var a := absf(c)
	var band := minf(BAND, half * 0.25)
	var out: float
	if a <= _LANES:
		out = a / _LANES * (half - band)
	elif a <= _KERB:
		out = half - band + (a - _LANES) / (_KERB - _LANES) * band
	else:
		out = half + (a - _KERB) / (0.5 - _KERB) * pavement
	return out * signf(c)


## The height of a tile's [param y]: the asphalt at [constant LIFT], the pavement at the kerb's
## height, the tile's base sunk below the ground.
static func _height(y: float) -> float:
	return LIFT + (y - _ROAD_Y) / (_TOP_Y - _ROAD_Y) * (RoadMarking.KERB_HEIGHT - LIFT)


## Adds the straight tile between frames [param a] and [param b]: the tile's length along the
## way from one to the other, its cross-section to their right; without the kerbs and pavement
## when [param kerbs] is false.
static func _sweep(st: SurfaceTool, tile: Array, a: Array, b: Array, half: float,
		pavement: float, kerbs: bool) -> void:
	var positions: PackedVector3Array = tile[0]
	var normals: PackedVector3Array = tile[1]
	var uvs: PackedVector2Array = tile[2]
	var along: Vector3 = (b[0] - a[0])
	along.y = 0.0
	along = along.normalized()
	var right: Vector3 = (a[1] + b[1]).normalized()
	for i in range(0, positions.size(), 3):
		if not kerbs and not _road_only(positions, i):
			continue
		for k in 3:
			var p := positions[i + k]
			var n := normals[i + k]
			var t := p.x + 0.5
			var across := _across(p.z, half, pavement)
			var at: Vector3 = (a[0] + a[1] * across).lerp(b[0] + b[1] * across, t)
			st.set_normal((along * n.x + Vector3.UP * n.y + right * n.z).normalized())
			st.set_uv(uvs[i + k])
			st.add_vertex(at + Vector3.UP * _height(p.y))


## Whether the triangle from [param i] is part of the asphalt, not the kerb or the pavement.
static func _road_only(positions: PackedVector3Array, i: int) -> bool:
	for k in 3:
		var p := positions[i + k]
		if absf(p.z) > _KERB + _EPS or p.y > _ROAD_Y + _EPS:
			return false
	return true


static func _begin(tile: Array) -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	if tile[3]:
		st.set_material(tile[3])
	return st


## The tile at [param path] as triangles in tile units: one unit square, the asphalt at
## [constant _ROAD_Y] and the pavement at [constant _TOP_Y], centred on the origin, the straight
## road running along X. The ends where tiles meet, the base, and the centre line are left out or
## painted over. Empty when it does not load.
static func _tile(path: String) -> Array:
	if _tiles.has(path):
		return _tiles[path]
	var out: Array = []
	var mesh := KitModels.mesh(path)
	if mesh and mesh.get_surface_count() > 0:
		out = _read(mesh)
	_tiles[path] = out
	return out


static func _read(mesh: ArrayMesh) -> Array:
	var box := mesh.get_aabb()
	var size := box.size
	if size.x <= 0.0 or size.z <= 0.0 or size.y <= 0.0:
		return []
	var centre := box.get_center()
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	if indices.is_empty():
		indices = PackedInt32Array(range(vertices.size()))
	var to_tile := func(v: Vector3) -> Vector3:
		return Vector3((v.x - centre.x) / size.x, (v.y - box.position.y) / size.y * _TOP_Y,
			(v.z - centre.z) / size.z)
	var positions := PackedVector3Array()
	var out_normals := PackedVector3Array()
	var out_uvs := PackedVector2Array()
	var asphalt := Vector2(-1, -1)
	var lines: Array[int] = []
	for i in range(0, indices.size(), 3):
		var tri: Array[Vector3] = []
		for k in 3:
			tri.append(to_tile.call(vertices[indices[i + k]]))
		if _hidden(tri):
			continue
		var at := positions.size()
		for k in 3:
			positions.append(tri[k])
			out_normals.append(normals[indices[i + k]] if normals.size() > 0 else Vector3.UP)
			out_uvs.append(uvs[indices[i + k]] if uvs.size() > 0 else Vector2.ZERO)
		if _flat_at(tri, _ROAD_Y):
			if _centre_line(tri):
				lines.append(at)
			elif asphalt.x < 0.0 and _lane_asphalt(tri):
				asphalt = out_uvs[at]
	if asphalt.x >= 0.0:
		for at in lines:
			for k in 3:
				out_uvs[at + k] = asphalt
	return [positions, out_normals, out_uvs, mesh.surface_get_material(0)]


## Faces never seen once tiles are laid end to end on the ground: the base, and the straight
## tile's ends.
static func _hidden(tri: Array[Vector3]) -> bool:
	if _flat_at(tri, 0.0):
		return true
	for x in [-0.5, 0.5]:
		if absf(tri[0].x - x) < _EPS and absf(tri[1].x - x) < _EPS and absf(tri[2].x - x) < _EPS:
			return true
	return false


static func _flat_at(tri: Array[Vector3], y: float) -> bool:
	return absf(tri[0].y - y) < _EPS and absf(tri[1].y - y) < _EPS and absf(tri[2].y - y) < _EPS


## A thin strip along the middle of either axis: the kit's centre line.
static func _centre_line(tri: Array[Vector3]) -> bool:
	for axis in [0, 2]:
		var thin := true
		for p in tri:
			if absf(p[axis]) > 0.02:
				thin = false
		if thin:
			return true
	return false


## A triangle well inside a lane, away from the line and the band.
static func _lane_asphalt(tri: Array[Vector3]) -> bool:
	for p in tri:
		var a := absf(p.z)
		if a < 0.02 or a > _LANES + _EPS:
			return false
	return true
