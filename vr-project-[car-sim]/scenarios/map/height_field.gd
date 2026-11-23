class_name HeightField
extends RefCounted
## A grid of heights over the ground plane: [member count_x] by [member count_z] points
## [member cell] metres apart, the first at [member origin] (x, z), held row by row along X in
## [member heights]. Between the points the height is bilinear. Pure data, built and read on any
## thread; a [Terrain] builds one from its heightmap, its shapes, and the roads.

var origin := Vector2.ZERO
var cell := 1.0
var count_x := 2
var count_z := 2
var heights := PackedFloat32Array()


func _init(p_origin := Vector2.ZERO, p_cell := 1.0, p_count_x := 2, p_count_z := 2,
		fill := 0.0) -> void:
	origin = p_origin
	cell = maxf(p_cell, 0.01)
	count_x = maxi(p_count_x, 2)
	count_z = maxi(p_count_z, 2)
	heights.resize(count_x * count_z)
	heights.fill(fill)


## A field covering [param size] metres (x, z) centred on [param centre], its points
## [param p_cell] metres apart; it reaches at least [param size], a whole number of cells.
static func covering(size: Vector2, p_cell := 1.0, centre := Vector2.ZERO) -> HeightField:
	var c := maxf(p_cell, 0.01)
	var nx := maxi(ceili(size.x / c - 0.0001), 1) + 1
	var nz := maxi(ceili(size.y / c - 0.0001), 1) + 1
	var span := Vector2(nx - 1, nz - 1) * c
	return HeightField.new(centre - span / 2.0, c, nx, nz)


## The field's extent on the ground: x and z.
func rect() -> Rect2:
	return Rect2(origin, Vector2(count_x - 1, count_z - 1) * cell)


func get_point(i: int, j: int) -> float:
	return heights[j * count_x + i]


func set_point(i: int, j: int, h: float) -> void:
	heights[j * count_x + i] = h


## The grid point [param i], [param j] with its height.
func point(i: int, j: int) -> Vector3:
	return Vector3(origin.x + i * cell, get_point(i, j), origin.y + j * cell)


## The height at [param x], [param z]: bilinear between the four grid points round it, the edge's
## height beyond the field.
func height_at(x: float, z: float) -> float:
	var fx := clampf((x - origin.x) / cell, 0.0, count_x - 1)
	var fz := clampf((z - origin.y) / cell, 0.0, count_z - 1)
	var i := mini(floori(fx), count_x - 2)
	var j := mini(floori(fz), count_z - 2)
	var tx := fx - i
	var tz := fz - j
	var a := lerpf(get_point(i, j), get_point(i + 1, j), tx)
	var b := lerpf(get_point(i, j + 1), get_point(i + 1, j + 1), tx)
	return lerpf(a, b, tz)


## The surface's upward normal at [param x], [param z], from the slope across one cell either way.
func normal_at(x: float, z: float) -> Vector3:
	var dx := (height_at(x + cell, z) - height_at(x - cell, z)) / (2.0 * cell)
	var dz := (height_at(x, z + cell) - height_at(x, z - cell)) / (2.0 * cell)
	return Vector3(-dx, 1.0, -dz).normalized()


## The normal at grid point [param i], [param j].
func point_normal(i: int, j: int) -> Vector3:
	# The grid's own neighbours, the edge's height beyond it: what [method normal_at] samples
	# there, without the four bilinear lookups.
	var dx := (get_point(mini(i + 1, count_x - 1), j) - get_point(maxi(i - 1, 0), j)) / (2.0 * cell)
	var dz := (get_point(i, mini(j + 1, count_z - 1)) - get_point(i, maxi(j - 1, 0))) / (2.0 * cell)
	return Vector3(-dx, 1.0, -dz).normalized()


## Calls [param change] ([code](x, z, height) -> height[/code]) for every grid point within
## [param area] (x, z), keeping what it returns.
func stamp(area: Rect2, change: Callable) -> void:
	var within := span(area)
	if within.is_empty():
		return
	for j in range(within[1], within[3] + 1):
		var z := origin.y + j * cell
		for i in range(within[0], within[2] + 1):
			var at := j * count_x + i
			heights[at] = change.call(origin.x + i * cell, z, heights[at])


## The grid points' indices within [param area] (x, z): [code][i0, j0, i1, j1][/code], inclusive;
## empty when none are.
func span(area: Rect2) -> PackedInt32Array:
	var i0 := maxi(ceili((area.position.x - origin.x) / cell), 0)
	var j0 := maxi(ceili((area.position.y - origin.y) / cell), 0)
	var i1 := mini(floori((area.end.x - origin.x) / cell), count_x - 1)
	var j1 := mini(floori((area.end.y - origin.y) / cell), count_z - 1)
	if i1 < i0 or j1 < j0:
		return PackedInt32Array()
	return PackedInt32Array([i0, j0, i1, j1])


## Adds [param image] stretched over the whole field, or over [param over] (x, z) when given, as
## for a part of a larger field; its red channel times [param scale]: black adds nothing, white
## [param scale] metres. Bilinear between the image's pixels.
func add_image(image: Image, scale: float, over := Rect2()) -> void:
	if image == null or image.is_empty():
		return
	var img := image
	if img.is_compressed():
		img = image.duplicate() as Image
		img.decompress()
	var w := img.get_width()
	var h := img.get_height()
	var whole := over if over.has_area() else rect()
	for j in count_z:
		var v := clampf((origin.y + j * cell - whole.position.y) / whole.size.y, 0.0, 1.0) \
			* (h - 1)
		var y0 := mini(floori(v), maxi(h - 2, 0))
		var ty := v - y0
		for i in count_x:
			var u := clampf((origin.x + i * cell - whole.position.x) / whole.size.x, 0.0, 1.0) \
				* (w - 1)
			var x0 := mini(floori(u), maxi(w - 2, 0))
			var tx := u - x0
			var x1 := mini(x0 + 1, w - 1)
			var y1 := mini(y0 + 1, h - 1)
			var top := lerpf(img.get_pixel(x0, y0).r, img.get_pixel(x1, y0).r, tx)
			var bottom := lerpf(img.get_pixel(x0, y1).r, img.get_pixel(x1, y1).r, tx)
			heights[j * count_x + i] += lerpf(top, bottom, ty) * scale


## Where the ray from [param from] along [param direction] first meets the surface, within
## [param reach] metres; null when it does not. Marched a cell at a time, then halved down.
func intersect_ray(from: Vector3, direction: Vector3, reach := 2000.0) -> Variant:
	var dir := direction.normalized()
	var step := cell
	var previous := from
	var above := previous.y >= height_at(previous.x, previous.z)
	var travelled := 0.0
	while travelled < reach:
		travelled += step
		var at := from + dir * travelled
		var now_above := at.y >= height_at(at.x, at.z)
		if above and not now_above:
			var lo := previous
			var hi := at
			for k in 16:
				var mid := (lo + hi) * 0.5
				if mid.y >= height_at(mid.x, mid.z):
					lo = mid
				else:
					hi = mid
			return (lo + hi) * 0.5
		above = now_above
		previous = at
	return null


## The part of the field from grid point [param i0], [param j0] to [param i1], [param j1]
## inclusive, its heights its own.
func part(i0: int, j0: int, i1: int, j1: int) -> HeightField:
	var out := HeightField.new(origin + Vector2(i0, j0) * cell, cell, i1 - i0 + 1, j1 - j0 + 1)
	for j in out.count_z:
		for i in out.count_x:
			out.heights[j * out.count_x + i] = heights[(j0 + j) * count_x + i0 + i]
	return out


## Writes [param other]'s heights over this field's from grid point [param i0], [param j0]: a part
## of the same grid, as [method part] gives.
func paste(other: HeightField, i0: int, j0: int) -> void:
	for j in other.count_z:
		for i in other.count_x:
			heights[(j0 + j) * count_x + i0 + i] = other.heights[j * other.count_x + i]


## A copy, its heights its own.
func copy() -> HeightField:
	var out := HeightField.new(origin, cell, count_x, count_z)
	out.heights = heights.duplicate()
	return out
