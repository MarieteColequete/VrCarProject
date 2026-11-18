class_name Geo
extends RefCounted
## The framework's geometry, as pure functions of plain values: boxes and footprints on the ground,
## points in boxes, segment crossings. Detection, scoring and traffic all call these, so a rule
## judges the same shape the same way wherever it is used, on any thread.
##
## A ground box is an oriented rectangle on the ground plane (X, Z as a [Vector2]): its centre, the
## unit axis along its length, and half its length and width.


## Whether [param point] lies inside the box at [param box] (its transform) with half extents
## [param half], grown by [param margin] on the ground plane but not vertically.
static func point_in_box(box: Transform3D, half: Vector3, point: Vector3, margin := 0.0) -> bool:
	var local := box.affine_inverse() * point
	return absf(local.x) <= half.x + margin and absf(local.z) <= half.z + margin \
		and absf(local.y) <= half.y


## The ground box of a box at [param box] with half extents [param half], as
## [code][centre, along, half_length, half_width][/code]; the length runs along the box's Z.
static func ground_box(box: Transform3D, half: Vector3) -> Array:
	var z := Vector2(box.basis.z.x, box.basis.z.z)
	var x := Vector2(box.basis.x.x, box.basis.x.z)
	var along := z.normalized() if not z.is_zero_approx() else Vector2(0, 1)
	return [Vector2(box.origin.x, box.origin.z), along, half.z * z.length(), half.x * x.length()]


## Whether two ground boxes overlap, by the separating axis test on their four axes.
static func boxes_overlap(c1: Vector2, along1: Vector2, half_len1: float, half_wid1: float,
		c2: Vector2, along2: Vector2, half_len2: float, half_wid2: float) -> bool:
	var across1 := Vector2(-along1.y, along1.x)
	var across2 := Vector2(-along2.y, along2.x)
	var d := c2 - c1
	for axis: Vector2 in [along1, across1, along2, across2]:
		var r1 := absf(axis.dot(along1)) * half_len1 + absf(axis.dot(across1)) * half_wid1
		var r2 := absf(axis.dot(along2)) * half_len2 + absf(axis.dot(across2)) * half_wid2
		if absf(axis.dot(d)) > r1 + r2:
			return false
	return true


## Whether a body standing at [param body] (its transform, the box centred [param body_height]
## half up) with ground size [param size] (width, length) and height [param height] overlaps the
## box at [param box] with half extents [param half]: on the ground plane and in height.
static func body_in_box(body: Transform3D, size: Vector2, height: float, box: Transform3D,
		half: Vector3) -> bool:
	var top := body.origin.y + height
	var box_y := box.origin.y
	var box_half_y := half.y * box.basis.y.length()
	if top < box_y - box_half_y or body.origin.y > box_y + box_half_y:
		return false
	var a := ground_box(body, Vector3(size.x * 0.5, 0.0, size.y * 0.5))
	var b := ground_box(box, half)
	return boxes_overlap(a[0], a[1], a[2], a[3], b[0], b[1], b[2], b[3])


## The four corners of a [param width] by [param length] rectangle centred on [param t], on the
## ground at [param t]'s height: front left, front right, rear right, rear left (front is -Z).
static func ground_rect(t: Transform3D, width: float, length: float) -> PackedVector3Array:
	var hw := width * 0.5
	var hl := length * 0.5
	var out := PackedVector3Array()
	for local in [Vector3(-hw, 0, -hl), Vector3(hw, 0, -hl), Vector3(hw, 0, hl), Vector3(-hw, 0, hl)]:
		# Flattened to the centre's height, so a tilted body does not lift its footprint.
		var p: Vector3 = t * local
		p.y = t.origin.y
		out.append(p)
	return out


## How far, in metres, the furthest of [param points] lies outside a [param size] (width,
## length) rectangle centred on [param rect]; 0 when all are in.
static func overhang(rect: Transform3D, size: Vector2, points: PackedVector3Array) -> float:
	var inverse := rect.affine_inverse()
	var worst := 0.0
	for p in points:
		var local := inverse * p
		worst = maxf(worst, maxf(absf(local.x) - size.x * 0.5, absf(local.z) - size.y * 0.5))
	return worst


## Degrees between [param forward] and [param into] on the ground plane, and between it and the
## opposite direction, as [code]Vector2(nose_in, reversed)[/code].
static func facing_angles(into: Vector3, forward: Vector3) -> Vector2:
	into.y = 0.0
	forward.y = 0.0
	into = into.normalized()
	forward = forward.normalized()
	return Vector2(rad_to_deg(forward.angle_to(into)), rad_to_deg(forward.angle_to(-into)))


## Where a point moving by [param move] from [param a] crosses the segment [param s0] to
## [param s1], as [code]Vector2(t, u)[/code]: the fraction along the move and along the segment.
## [code]Vector2(-1, -1)[/code] when it does not cross; a move that only reaches the segment's
## start line does not count, a move that ends on it does.
static func crossing(a: Vector2, move: Vector2, s0: Vector2, s1: Vector2) -> Vector2:
	var edge := s1 - s0
	var denom := move.cross(edge)
	if is_zero_approx(denom):
		return Vector2(-1, -1)
	var offset := s0 - a
	var t := offset.cross(edge) / denom
	var u := offset.cross(move) / denom
	if t <= 0.0 or t > 1.0 or u < 0.0 or u > 1.0:
		return Vector2(-1, -1)
	return Vector2(t, u)
