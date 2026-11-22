@tool
class_name TerrainShape
extends Node3D
## A shape a [Terrain] gives the land, on top of its heightmap, in tree order. A HILL raises the land
## by [member height] and a VALLEY lowers it, fully within [member radius] of the node and smoothly
## less out to [member falloff] beyond. A RAMP is a slope over its [member size] rectangle (x
## across, z along), from the node's own height at its +Z end to [member height] above that at its
## -Z end. A PLATEAU pulls the land within [member radius] to [member height] above the node,
## weighted out over [member falloff]. A ramp blends to the land over its falloff too. The editor
## draws the shape's outline; the game draws nothing.

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

const OUTLINE := Color(0.95, 0.75, 0.2)

var _outline: MeshInstance3D


func _ready() -> void:
	set_notify_transform(true)
	if Engine.is_editor_hint():
		_outline = MeshInstance3D.new()
		add_child(_outline, false, INTERNAL_MODE_BACK)
		_draw_outline()
	Terrain.notify_changed(self)


func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		_changed()


## Applies the shape to [param field], whose space [param placed] takes the shape's local space
## into.
func apply(field: HeightField, placed: Transform3D) -> void:
	var reach := _reach()
	var inverse := placed.affine_inverse()
	var corners: Array[Vector3] = [Vector3(-reach.x, 0, -reach.y), Vector3(reach.x, 0, -reach.y),
		Vector3(reach.x, 0, reach.y), Vector3(-reach.x, 0, reach.y)]
	var first := placed * corners[0]
	var area := Rect2(Vector2(first.x, first.z), Vector2.ZERO)
	for corner in corners:
		var at := placed * corner
		area = area.expand(Vector2(at.x, at.z))
	var base := placed.origin.y
	field.stamp(area, func(x: float, z: float, h: float) -> float:
		var local := inverse * Vector3(x, base, z)
		return change(local.x, local.z, h, base))


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
	if distance <= radius:
		return 1.0
	if falloff <= 0.0:
		return 0.0
	return 1.0 - smoothstep(radius, radius + falloff, distance)


## A ramp's share of its effect at [param x], [param z]: whole on its rectangle, easing to none over
## the falloff.
func box_weight(x: float, z: float) -> float:
	var dx := maxf(absf(x) - size.x / 2.0, 0.0)
	var dz := maxf(absf(z) - size.y / 2.0, 0.0)
	var d := Vector2(dx, dz).length()
	if d <= 0.0:
		return 1.0
	if falloff <= 0.0:
		return 0.0
	return 1.0 - smoothstep(0.0, falloff, d)


## Half the shape's reach on x and z, its falloff included.
func _reach() -> Vector2:
	if kind == Kind.RAMP:
		return size / 2.0 + Vector2.ONE * falloff
	return Vector2.ONE * (radius + falloff)


func _changed() -> void:
	if not is_inside_tree():
		return
	if _outline:
		_draw_outline()
	Terrain.notify_changed(self)


func _draw_outline() -> void:
	var mesh := ImmediateMesh.new()
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = OUTLINE
	material.no_depth_test = true
	var loops: Array = []
	if kind == Kind.RAMP:
		loops.append(_rect(size / 2.0))
		loops.append(_rect(size / 2.0 + Vector2.ONE * falloff))
	else:
		loops.append(_circle(radius))
		loops.append(_circle(radius + falloff))
	for loop: PackedVector3Array in loops:
		if loop.size() < 2:
			continue
		mesh.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, material)
		for p in loop:
			mesh.surface_add_vertex(p)
		mesh.surface_end()
	_outline.mesh = mesh


static func _circle(r: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	if r <= 0.0:
		return out
	for k in 49:
		var a := TAU * k / 48.0
		out.append(Vector3(cos(a) * r, 0.0, sin(a) * r))
	return out


func _rect(half: Vector2) -> PackedVector3Array:
	var out := PackedVector3Array([Vector3(-half.x, 0, -half.y), Vector3(half.x, 0, -half.y),
		Vector3(half.x, 0, half.y), Vector3(-half.x, 0, half.y), Vector3(-half.x, 0, -half.y)])
	if kind == Kind.RAMP:
		# The arrow up the slope.
		out.append(Vector3(0, 0, half.y))
		out.append(Vector3(0, height, -half.y))
	return out
