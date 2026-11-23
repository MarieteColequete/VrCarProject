@tool
class_name TerrainShape
extends Node3D
## A shape a [Terrain] gives the land, on top of its heightmap, in tree order. A HILL raises the land
## by [member height] and a VALLEY lowers it, fully within [member radius] of the node and smoothly
## less out to [member falloff] beyond. A RAMP is a slope over its [member size] rectangle (x
## across, z along), from the node's own height at its +Z end to [member height] above that at its
## -Z end. A PLATEAU pulls the land within [member radius] to [member height] above the node,
## weighted out over [member falloff]. A ramp blends to the land over its falloff too. In the
## editor the Map Kit draws its outline on the land and gives it handles
## ([method handles]); the game draws nothing.

enum Kind { HILL, VALLEY, RAMP, PLATEAU }

@export var kind := Kind.HILL:
	set(value):
		kind = value
		_changed()
## Metres: what a hill adds, a valley takes, a ramp climbs, or a plateau stands above the node.
@export var height := 5.0:
	set(value):
		height = value
		_changed()
## Metres of full effect round the node: a hill, valley, or plateau.
@export_range(0.0, 500.0, 0.5, "or_greater") var radius := 10.0:
	set(value):
		radius = value
		_changed()
## A ramp's rectangle, metres: x across, z along.
@export var size := Vector2(10, 30):
	set(value):
		size = value
		_changed()
## Metres beyond the full effect over which the shape blends to the land.
@export_range(0.0, 500.0, 0.5, "or_greater") var falloff := 20.0:
	set(value):
		falloff = value
		_changed()

## Emitted when the shape changes: its kind, a size, or where it stands.
signal shape_changed

## The handles' names: what each one drags.
const RADIUS := &"radius"
const FALLOFF := &"falloff"
const HEIGHT := &"height"
const LENGTH := &"length"
const WIDTH := &"width"


func _ready() -> void:
	set_notify_transform(true)
	Terrain.notify_changed(self)


func _exit_tree() -> void:
	Terrain.notify_leaving(self)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_changed()


## The ground the shape reaches, its falloff included, as a rectangle (x, z) in the space
## [param placed] takes the shape's local space into.
func area(placed: Transform3D) -> Rect2:
	return Geo.ground_area(placed, _reach())


## The handles that size the shape, each [code]{name, local}[/code]: what it drags (one of the
## handle names) and where it sits in the shape's own space, on its base. The height handle sits
## at the shape's [method target] over land [param ground] high at its centre, without the shape;
## the editor lifts the others onto the land.
func handles(ground := 0.0) -> Array[Dictionary]:
	if kind == Kind.RAMP:
		var half := size / 2.0
		return [{name = LENGTH, local = Vector3(0.0, 0.0, -half.y)},
			{name = WIDTH, local = Vector3(half.x, 0.0, 0.0)},
			{name = HEIGHT, local = Vector3(0.0, target(ground), -half.y)},
			{name = FALLOFF, local = Vector3(half.x + falloff, 0.0, 0.0)}]
	return [{name = RADIUS, local = Vector3(radius, 0.0, 0.0)},
		{name = FALLOFF, local = Vector3(radius + falloff, 0.0, 0.0)},
		{name = HEIGHT, local = Vector3(0.0, target(ground), 0.0)}]


## The value the handle [param handle] gives with it dragged to [param local] in the shape's own
## space, over land [param ground] high at its centre: the reverse of [method handles]. Sizes are
## never below nought; a hill or valley's height never below nought either, as which way it goes
## is its kind.
func value_from(handle: StringName, local: Vector3, ground := 0.0) -> float:
	var flat := Vector2(local.x, local.z)
	match handle:
		RADIUS:
			return maxf(flat.length(), 0.0)
		FALLOFF:
			if kind == Kind.RAMP:
				return maxf(absf(local.x) - size.x / 2.0, 0.0)
			return maxf(flat.length() - radius, 0.0)
		LENGTH:
			return maxf(absf(local.z) * 2.0, 0.0)
		WIDTH:
			return maxf(absf(local.x) * 2.0, 0.0)
		HEIGHT:
			match kind:
				Kind.HILL:
					return maxf(local.y - ground, 0.0)
				Kind.VALLEY:
					return maxf(ground - local.y, 0.0)
			return local.y
	return 0.0


## The land's height at the shape's centre without the shape, in its own space, from
## [param with_shape], the height there with it: a hill or valley adds its whole height at its
## centre; the others aim at their own height, so need none.
func ground_under(with_shape: float) -> float:
	match kind:
		Kind.HILL:
			return with_shape - height
		Kind.VALLEY:
			return with_shape + height
	return with_shape


## Reads the handle [param handle]'s value off the shape.
func handle_value(handle: StringName) -> float:
	match handle:
		RADIUS:
			return radius
		FALLOFF:
			return falloff
		LENGTH:
			return size.y
		WIDTH:
			return size.x
		HEIGHT:
			return height
	return 0.0


## Sets the handle [param handle]'s value on the shape.
func set_handle_value(handle: StringName, value: float) -> void:
	match handle:
		RADIUS:
			radius = value
		FALLOFF:
			falloff = value
		LENGTH:
			size = Vector2(size.x, value)
		WIDTH:
			size = Vector2(value, size.y)
		HEIGHT:
			height = value


## The property the handle [param handle] changes, and its value then, for undo.
static func handle_property(handle: StringName) -> StringName:
	return &"size" if handle == LENGTH or handle == WIDTH else handle


## The shape's outline in its own space, flat on its base: the full effect's ring or rectangle,
## then the falloff's; a ramp adds its arrow up the slope.
func outline_loops() -> Array[PackedVector3Array]:
	var out: Array[PackedVector3Array] = []
	if kind == Kind.RAMP:
		out.append(_rect(size / 2.0))
		out.append(_rect(size / 2.0 + Vector2.ONE * falloff))
		var half := size.y / 2.0
		out.append(PackedVector3Array([Vector3(0, 0, half), Vector3(0, 0, -half),
			Vector3(-size.x * 0.15, 0, -half + size.x * 0.2), Vector3(0, 0, -half),
			Vector3(size.x * 0.15, 0, -half + size.x * 0.2)]))
	else:
		out.append(_circle(radius))
		out.append(_circle(radius + falloff))
	return out


## [param loops] (in the shape's space) lifted onto the land: [param land] gives the land's height
## in the shape's space at a point of it, and each point sits [param above] metres over it.
static func drape(loops: Array[PackedVector3Array], land: Callable, above := 0.05) \
		-> Array[PackedVector3Array]:
	var out: Array[PackedVector3Array] = []
	for loop in loops:
		var lifted := PackedVector3Array()
		for p in loop:
			lifted.append(Vector3(p.x, float(land.call(p)) + above, p.z))
		out.append(lifted)
	return out


## The height the shape aims at, in its own space, over land [param ground] high at its centre: a
## hill's top, a valley's floor, a plateau's level, or a ramp's top end.
func target(ground: float) -> float:
	match kind:
		Kind.HILL:
			return ground + height
		Kind.VALLEY:
			return ground - height
	return height


## Applies the shape to [param field], whose space [param placed] takes the shape's local space
## into.
func apply(field: HeightField, placed: Transform3D) -> void:
	var span := field.span(area(placed))
	if span.is_empty():
		return
	var inverse := placed.affine_inverse()
	var base := placed.origin.y
	# Worked on a copy of the heights and put back once: written through the field, each point
	# would copy them all.
	var heights := field.heights
	for j in range(span[1], span[3] + 1):
		var z := field.origin.y + j * field.cell
		for i in range(span[0], span[2] + 1):
			var k := j * field.count_x + i
			var local := inverse * Vector3(field.origin.x + i * field.cell, base, z)
			heights[k] = change(local.x, local.z, heights[k], base)
	field.heights = heights


## The height of land at [param h] once the shape acts on it at [param x], [param z] in the shape's
## own space, the node standing at [param base].
func change(x: float, z: float, h: float, base: float) -> float:
	match kind:
		Kind.HILL:
			return h + height * radial_weight(Vector2(x, z).length())
		Kind.VALLEY:
			return h - height * radial_weight(Vector2(x, z).length())
		Kind.PLATEAU:
			return lerpf(h, base + height, radial_weight(Vector2(x, z).length()))
		Kind.RAMP:
			var w := box_weight(x, z)
			if w <= 0.0:
				return h
			var t := clampf(0.5 - z / maxf(size.y, 0.01), 0.0, 1.0)
			return lerpf(h, base + height * t, w)
	return h


## The share of the shape's effect at [param distance] from its centre: whole within the radius,
## easing to none over the falloff.
func radial_weight(distance: float) -> float:
	return Geo.ease_out(radius, radius + falloff, distance)


## A ramp's share of its effect at [param x], [param z]: whole on its rectangle, easing to none over
## the falloff.
func box_weight(x: float, z: float) -> float:
	var dx := maxf(absf(x) - size.x / 2.0, 0.0)
	var dz := maxf(absf(z) - size.y / 2.0, 0.0)
	return Geo.ease_out(0.0, falloff, Vector2(dx, dz).length())


## Half the shape's reach on x and z, its falloff included.
func _reach() -> Vector2:
	if kind == Kind.RAMP:
		return size / 2.0 + Vector2.ONE * falloff
	return Vector2.ONE * (radius + falloff)


func _changed() -> void:
	if not is_inside_tree():
		return
	shape_changed.emit()
	update_gizmos()
	Terrain.notify_changed(self)


static func _circle(r: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	if r <= 0.0:
		return out
	for k in 49:
		var a := TAU * k / 48.0
		out.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
	return out


## A rectangle [param half] either side of the centre, a point every metre or so along each side,
## so it can follow the land.
static func _rect(half: Vector2) -> PackedVector3Array:
	var corners := [Vector3(-half.x, 0, -half.y), Vector3(half.x, 0, -half.y),
		Vector3(half.x, 0, half.y), Vector3(-half.x, 0, half.y), Vector3(-half.x, 0, -half.y)]
	var out := PackedVector3Array()
	for k in 4:
		var a: Vector3 = corners[k]
		var b: Vector3 = corners[k + 1]
		var steps := clampi(ceili(a.distance_to(b)), 1, 64)
		for t in steps:
			out.append(a.lerp(b, float(t) / steps))
	out.append(corners[4])
	return out
