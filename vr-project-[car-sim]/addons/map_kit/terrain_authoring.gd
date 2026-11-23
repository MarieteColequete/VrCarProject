@tool
class_name TerrainAuthoring
extends RefCounted
## A map's terrain as Map Kit shapes it: adding the land, draping the roads and places on it no
## steeper than a grade, and editing the terrain shapes.

## What a terrain shape of [param kind] is sized by, as its handles name them
## ([method TerrainShape.handles]): its height, its radius or a ramp's length and width, and its
## falloff.
static func shape_fields(kind: TerrainShape.Kind) -> Array[StringName]:
	if kind == TerrainShape.Kind.RAMP:
		return [TerrainShape.HEIGHT, TerrainShape.LENGTH, TerrainShape.WIDTH, TerrainShape.FALLOFF]
	return [TerrainShape.HEIGHT, TerrainShape.RADIUS, TerrainShape.FALLOFF]


## Sets [param shape]'s [param field] to [param value]: [code]kind[/code], or one of
## [method shape_fields] in metres.
static func set_shape(shape: TerrainShape, field: StringName, value: float) -> MapKitTools.Edit:
	var edit := MapKitTools.Edit.new()
	if shape == null:
		return edit
	match field:
		&"kind":
			edit.set_value(shape, &"kind", int(value))
		TerrainShape.LENGTH:
			edit.set_value(shape, &"size", Vector2(shape.size.x, value))
		TerrainShape.WIDTH:
			edit.set_value(shape, &"size", Vector2(value, shape.size.y))
		_:
			edit.set_value(shape, field, value)
	return edit


## Stands [param shape] on [param map]'s land under it, the land as it is without the shape and
## the roads, so a plateau or a ramp starts from the ground. Empty when the map has no terrain.
static func snap_shape_base(map: Node, shape: TerrainShape) -> MapKitTools.Edit:
	var edit := MapKitTools.Edit.new()
	var terrain := Terrain.of(map)
	if terrain == null or shape == null:
		return edit
	var at := RoadMap.to_map(shape, map).origin
	var ground := terrain.land_height_at(at, terrain.land(shape))
	var parent := RoadMap.to_map(shape.get_parent(), map)
	var local := parent.affine_inverse() * Vector3(at.x, ground, at.z)
	edit.set_value(shape, &"position", Vector3(shape.position.x, local.y, shape.position.z))
	return edit


## Adds a [Terrain] to [param map] over its environment's ground, whose flat ground it turns off.
## Empty when the map has a terrain already.
static func add_terrain(map: Node) -> MapKitTools.Edit:
	var edit := MapKitTools.Edit.new()
	if map == null or Terrain.of(map) != null:
		return edit
	var terrain := Terrain.new()
	terrain.name = "Terrain"
	for node in MapKitTools.nodes_of(map):
		if node is RoadEnvironment:
			var environment := node as RoadEnvironment
			terrain.size = environment.ground_size
			terrain.position = RoadMap.to_map(environment, map) * environment.ground_offset
			if environment.ground:
				edit.set_value(environment, &"ground", false)
	edit.add(map, terrain)
	return edit


## Sets the heights of [param nodes] and everything under them (all of [param map]'s when empty)
## from the map's [Terrain], without its roads: a road's curve, redrawn a point every
## [constant RoadSegment.STEP] metres, follows the land smoothed to no steeper than
## [param max_grade] (rise over run), its ends held at the junctions they join; a junction stands
## on the land at its centre; lanes and markings, redrawn the same way, lie on the road or junction
## under them or else on the land; spawns, props, assets, signs, lights, and checkpoints stand on
## the same. Empty when the map has no terrain.
static func drape(map: Node, nodes: Array = [], max_grade := 0.12) -> MapKitTools.Edit:
	var edit := MapKitTools.Edit.new()
	var terrain := Terrain.of(map)
	if terrain == null:
		return edit
	var land := terrain.land()
	var picked: Array[Node] = []
	for node: Node in (nodes if not nodes.is_empty() else MapKitTools.nodes_of(map)):
		for inner in MapKitTools.with_descendants(node):
			if not picked.has(inner):
				picked.append(inner)
	# The junctions first: the roads' ends are held at their heights.
	var junction_y := {}
	for node in MapKitTools.nodes_of(map):
		if node is RoadJunction:
			var junction := node as RoadJunction
			var placed := RoadMap.to_map(junction, map)
			if picked.has(junction):
				placed.origin.y = terrain.land_height_at(placed.origin, land)
				edit.set_value(junction, &"position", (RoadMap.to_map(junction.get_parent(), map)
					.affine_inverse() * placed).origin)
			junction_y[junction] = placed
	# Every road's centre line in the map's space, as it will be.
	var lines: Array = []
	for node in MapKitTools.nodes_of(map):
		if not node is RoadSegment:
			continue
		var road := node as RoadSegment
		var into := RoadMap.to_map(road, map)
		var reach := road.width() / 2.0 + (road.pavement if road.kerbs else 0.0)
		if not picked.has(road):
			var points := PackedVector3Array()
			for frame: Array in road.frames():
				points.append(into * (frame[0] as Vector3))
			lines.append([points, reach])
			continue
		var points := _resampled(road.curve, RoadSegment.STEP, into)
		if points.size() < 2:
			continue
		var heights := PackedFloat32Array()
		for point in points:
			heights.append(terrain.land_height_at(point, land))
		var pins := {}
		for end: int in [0, points.size() - 1]:
			var held: Variant = _junction_height(points[end], junction_y)
			if held != null:
				pins[end] = held
		heights = graded(points, heights, max_grade, pins)
		var curve := Curve3D.new()
		var back := into.affine_inverse()
		for i in points.size():
			points[i].y = heights[i]
			curve.add_point(back * points[i])
		edit.set_value(road, &"curve", curve)
		lines.append([points, reach])
	var surface := func(point: Vector3) -> float:
		return _surface_height(point, junction_y, lines, terrain, land)
	for node in picked:
		if node is TrafficLane or node is RoadMarking:
			var path := node as Path3D
			if path.curve == null or path.curve.point_count < 2:
				continue
			var into := RoadMap.to_map(path, map)
			var points := _resampled(path.curve, RoadSegment.STEP, into)
			var curve := Curve3D.new()
			var back := into.affine_inverse()
			for point in points:
				point.y = surface.call(point)
				curve.add_point(back * point)
			edit.set_value(path, &"curve", curve)
		elif node is MapSpawn or node is Prop or node is MapAsset or node is RoadSign \
				or node is Scenery or node is TrafficLight or node is Checkpoint:
			var placed := RoadMap.to_map(node, map)
			placed.origin.y = surface.call(placed.origin)
			edit.set_value(node, &"position", (RoadMap.to_map(node.get_parent(), map).affine_inverse()
				* placed).origin)
	return edit


## [param heights] along [param points] (the same count) made no steeper than [param grade] between
## neighbours, measured across the ground: halfway between the highest and the lowest such
## profiles under and over the heights, then held at [param pins] (index to height) and eased away
## from them.
static func graded(points: PackedVector3Array, heights: PackedFloat32Array, grade: float,
		pins := {}) -> PackedFloat32Array:
	var n := heights.size()
	var rise := PackedFloat32Array()
	for i in n - 1:
		rise.append(grade * Vector2(points[i + 1].x - points[i].x,
			points[i + 1].z - points[i].z).length())
	var low := heights.duplicate()
	var high := heights.duplicate()
	for i in range(1, n):
		low[i] = minf(low[i], low[i - 1] + rise[i - 1])
		high[i] = maxf(high[i], high[i - 1] - rise[i - 1])
	for i in range(n - 2, -1, -1):
		low[i] = minf(low[i], low[i + 1] + rise[i])
		high[i] = maxf(high[i], high[i + 1] - rise[i])
	var out := PackedFloat32Array()
	for i in n:
		out.append((low[i] + high[i]) * 0.5)
	if pins.has(0):
		out[0] = pins[0]
		for i in range(1, n):
			out[i] = clampf(out[i], out[i - 1] - rise[i - 1], out[i - 1] + rise[i - 1])
	if pins.has(n - 1):
		out[n - 1] = pins[n - 1]
		for i in range(n - 2, -1, -1):
			out[i] = clampf(out[i], out[i + 1] - rise[i], out[i + 1] + rise[i])
	return out


## [param curve]'s points, every [param step] metres or a little less and at both ends, taken by
## [param into].
static func _resampled(curve: Curve3D, step: float, into: Transform3D) -> PackedVector3Array:
	var out := PackedVector3Array()
	if curve == null or curve.point_count < 2:
		return out
	var length := curve.get_baked_length()
	var count := maxi(ceili(length / step - 0.001), 1)
	for k in count + 1:
		out.append(into * curve.sample_baked(length * k / count))
	return out


## The height of the junction arm end [param point] meets, from [param junction_y] (junction to its
## transform in the map's space); null when it meets none.
static func _junction_height(point: Vector3, junction_y: Dictionary) -> Variant:
	for junction: RoadJunction in junction_y:
		var placed: Transform3D = junction_y[junction]
		for arm in junction.arms():
			var end := placed * junction.arm_end(arm).origin
			if Vector2(end.x - point.x, end.z - point.z).length() <= RoadNetwork.JOIN:
				return placed.origin.y
	return null


## The height of what stands under [param point]: a junction's pad, a road's centre line within
## its reach across, or else the land.
static func _surface_height(point: Vector3, junction_y: Dictionary, lines: Array,
		terrain: Terrain, land: HeightField) -> float:
	for junction: RoadJunction in junction_y:
		var placed: Transform3D = junction_y[junction]
		if junction.distance_outside(placed.affine_inverse() * point) <= RoadKit.PAVEMENT:
			return placed.origin.y
	var best := INF
	var best_y := 0.0
	var at := Vector2(point.x, point.z)
	for line: Array in lines:
		var points: PackedVector3Array = line[0]
		for i in points.size() - 1:
			var a := Vector2(points[i].x, points[i].z)
			var d := Vector2(points[i + 1].x, points[i + 1].z) - a
			var t := Geo.along_segment(at, a, d)
			var off := at.distance_to(a + d * t)
			if off <= float(line[1]) and off < best:
				best = off
				best_y = lerpf(points[i].y, points[i + 1].y, t)
	if best < INF:
		return best_y
	return terrain.land_height_at(point, land)
