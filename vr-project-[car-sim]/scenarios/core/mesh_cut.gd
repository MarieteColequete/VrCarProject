class_name MeshCut
extends RefCounted
## Surgery on a model's meshes, as the player's car's dressing needs it: the triangles picked out
## of a mesh into one of their own, or taken away from it; texture coordinates laid across
## triangles box-wise, for materials the model's own coordinates do not suit; and the axis of a
## flat part, such as a wheel's disc. Static and pure but for [method cut_away], which changes the
## part it is given.


## The direction across the flattest extent of [param mesh]'s points: a disc's axis.
static func plane_normal(mesh: Mesh) -> Vector3:
	var points := PackedVector3Array()
	for surface in mesh.get_surface_count():
		points.append_array(mesh.surface_get_arrays(surface)[Mesh.ARRAY_VERTEX])
	if points.size() < 3:
		return Vector3.RIGHT
	var centre := Vector3.ZERO
	for p in points:
		centre += p
	centre /= points.size()
	# The covariance's two largest directions span the disc; the normal crosses them.
	var c := [[0.0, 0.0, 0.0], [0.0, 0.0, 0.0], [0.0, 0.0, 0.0]]
	for p in points:
		var d := p - centre
		for i in 3:
			for j in 3:
				c[i][j] += d[i] * d[j]
	var first := _largest(c, Vector3(0.3, 0.6, 0.7))
	var lambda := _apply(c, first).dot(first)
	for i in 3:
		for j in 3:
			c[i][j] -= lambda * first[i] * first[j]
	var second := _largest(c, first.cross(Vector3(0.1, 0.9, 0.4)).normalized())
	var normal := first.cross(second)
	return normal.normalized() if normal.length() > 0.0001 else Vector3.RIGHT


static func _largest(c: Array, start: Vector3) -> Vector3:
	var v := start.normalized()
	for i in 64:
		var next := _apply(c, v)
		if next.length() < 0.0000001:
			break
		v = next.normalized()
	return v


static func _apply(c: Array, v: Vector3) -> Vector3:
	return Vector3(c[0][0] * v.x + c[0][1] * v.y + c[0][2] * v.z,
		c[1][0] * v.x + c[1][1] * v.y + c[1][2] * v.z,
		c[2][0] * v.x + c[2][1] * v.y + c[2][2] * v.z)


## [param mesh] (unindexed triangles) with new texture coordinates laid across it: each triangle
## projected along the axis it most faces, in the space [param to_space] turns it into, one repeat
## each [param tile] metres; and tangents to match, for the normal maps.
static func box_mapped(mesh: ArrayMesh, to_space: Transform3D, tile: float) -> ArrayMesh:
	var out := ArrayMesh.new()
	var normal_to := to_space.basis.inverse().transposed()
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		arrays[Mesh.ARRAY_TEX_UV] = box_uvs(points, to_space, normal_to, tile)
		arrays[Mesh.ARRAY_TANGENT] = null
		var tool := SurfaceTool.new()
		tool.create_from_arrays(arrays)
		tool.generate_tangents()
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, tool.commit_to_arrays())
	return out


## The texture coordinates of the unindexed triangles [param points]: each corner of a triangle
## projected along the axis the triangle most faces, after [param to_space] (its normals turned by
## [param normal_to]), one unit each [param tile] metres.
static func box_uvs(points: PackedVector3Array, to_space: Transform3D, normal_to: Basis,
		tile: float) -> PackedVector2Array:
	var uvs := PackedVector2Array()
	uvs.resize(points.size())
	for t in range(0, points.size() - 2, 3):
		var a := to_space * points[t]
		var b := to_space * points[t + 1]
		var c := to_space * points[t + 2]
		var n := (normal_to * (points[t + 2] - points[t]).cross(points[t + 1] - points[t])).abs()
		for i in 3:
			var p: Vector3 = [a, b, c][i]
			var uv := Vector2(p.z, p.y) if n.x >= n.y and n.x >= n.z \
				else (Vector2(p.x, p.z) if n.y >= n.z else Vector2(p.x, p.y))
			uvs[t + i] = uv / tile
	return uvs


## Takes the triangles [param picks] picks out of [param part], which keeps its materials.
static func cut_away(part: MeshInstance3D, picks: Callable) -> void:
	var materials := surface_materials(part)
	var sources := []
	part.mesh = cut_mesh(part.mesh, picks, false, sources)
	for surface in sources.size():
		part.set_surface_override_material(surface, materials[sources[surface]])


## Each surface's material as [param part] draws it: its override, else the mesh's own.
static func surface_materials(part: MeshInstance3D) -> Array:
	var materials := []
	for surface in part.mesh.get_surface_count():
		var material := part.get_surface_override_material(surface)
		materials.append(material if material else part.mesh.surface_get_material(surface))
	return materials


## The triangles of [param mesh] that [param picks] picks (given their three corners), or with
## [param kept] false the ones it leaves, as a mesh of their own. A surface left with no triangles
## is dropped; [param sources] gets the source surface of each one made.
static func cut_mesh(mesh: Mesh, picks: Callable, kept: bool, sources: Array = []) -> ArrayMesh:
	var out := ArrayMesh.new()
	for surface in mesh.get_surface_count():
		var tool := SurfaceTool.new()
		tool.create_from(mesh, surface)
		tool.deindex()
		var arrays := tool.commit_to_arrays()
		var points: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var keep := PackedInt32Array()
		for t in range(0, points.size() - 2, 3):
			if picks.call(points[t], points[t + 1], points[t + 2]) == kept:
				keep.append_array([t, t + 1, t + 2])
		if keep.is_empty():
			continue
		if kept:
			# The glass on its own: only its own corners, unindexed.
			for column in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TANGENT,
					Mesh.ARRAY_TEX_UV, Mesh.ARRAY_TEX_UV2, Mesh.ARRAY_COLOR]:
				arrays[column] = _pick(arrays[column], keep, column == Mesh.ARRAY_TANGENT)
			arrays[Mesh.ARRAY_INDEX] = null
		else:
			arrays[Mesh.ARRAY_INDEX] = keep
		out.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		sources.append(surface)
	return out


static func _pick(column: Variant, rows: PackedInt32Array, tangent: bool) -> Variant:
	if column == null:
		return null
	if tangent:
		var out := PackedFloat32Array()
		for r in rows:
			out.append_array((column as PackedFloat32Array).slice(r * 4, r * 4 + 4))
		return out
	var picked: Variant = column.duplicate()
	picked.resize(rows.size())
	for i in rows.size():
		picked[i] = column[rows[i]]
	return picked


## The triangles of [param mesh] whose centroid [param keep] keeps, as a mesh of their own.
static func split_mesh(mesh: Mesh, keep: Callable) -> ArrayMesh:
	return cut_mesh(mesh, func(a: Vector3, b: Vector3, c: Vector3) -> bool:
		return not keep.call((a + b + c) / 3.0), false)


## [param mesh] whole, its triangles unindexed, ready for new texture coordinates.
static func unindexed(mesh: Mesh) -> ArrayMesh:
	return cut_mesh(mesh, func(_a: Vector3, _b: Vector3, _c: Vector3) -> bool: return true, true)
