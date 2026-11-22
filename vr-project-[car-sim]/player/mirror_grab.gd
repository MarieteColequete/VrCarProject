class_name MirrorGrab
extends RefCounted
## Setting a mirror with the hand, in VR. A gripping hand within [constant REACH] of a mirror's
## glass, and not on the steering wheel, takes hold of it; while held, moving the hand across the
## glass tilts it, to the right to turn the view right and up to turn it up, as pushing a real
## mirror's glass does. Pure state and geometry: the driver's view feeds it the hands and the
## mirrors' glass, and the car tilts the mirrors, so tests can drive it with made-up hands.

## How far from a mirror's glass a gripping hand takes hold, metres.
const REACH := 0.08
## How much the mirror tilts as the hand moves across its glass, radians per metre.
const PER_METRE := 2.5

## Each hand's hold: [code]{mirror, at}[/code], the mirror held and where the hand was across its
## glass last step, or null while it holds none.
var holds: Array = [null, null]


## Whether any hand holds a mirror.
func held() -> bool:
	return holds[0] != null or holds[1] != null


## A step with the mirrors' glass at [param glasses] (each a frame facing its +Z), the hands at
## [param hands] (two world positions), gripping as [param grips] says, and [param on_wheel] which
## hands hold the steering wheel: each mirror's tilt change, a [Vector2] (see
## [member CarMirror.tilt]), and the hands that have just taken hold, in [code]{tilts, taken}[/code].
func step(glasses: Array, hands: Array, grips: Array, on_wheel: Array) -> Dictionary:
	var tilts: Array[Vector2] = []
	tilts.resize(glasses.size())
	tilts.fill(Vector2.ZERO)
	var taken: Array[int] = []
	for i in 2:
		if not grips[i] or on_wheel[i]:
			holds[i] = null
			continue
		var at: Vector3 = hands[i]
		if holds[i] == null:
			var nearest := nearest_glass(glasses, at)
			if nearest >= 0:
				holds[i] = {mirror = nearest, at = across(glasses[nearest], at)}
				taken.append(i)
			continue
		var mirror: int = holds[i].mirror
		if mirror >= glasses.size():
			holds[i] = null
			continue
		var here := across(glasses[mirror], at)
		tilts[mirror] += (here - (holds[i].at as Vector2)) * PER_METRE
		holds[i].at = here
	return {tilts = tilts, taken = taken}


## The mirror whose glass in [param glasses] is nearest [param at] within [constant REACH], or -1.
static func nearest_glass(glasses: Array, at: Vector3) -> int:
	var best := -1
	var best_distance := REACH
	for m in glasses.size():
		var distance := ((glasses[m] as Transform3D).origin - at).length()
		if distance <= best_distance:
			best = m
			best_distance = distance
	return best


## Where [param at] is across the glass at [param glass], metres: x to the driver's right, y up.
## The glass faces the driver, so its own +X is to the driver's right.
static func across(glass: Transform3D, at: Vector3) -> Vector2:
	var local := glass.affine_inverse() * at
	return Vector2(local.x, local.y)


## The point on the glass at [param glass] nearest [param at]: where a holding hand is drawn.
static func on_glass(glass: Transform3D, at: Vector3) -> Vector3:
	var local := glass.affine_inverse() * at
	return glass * Vector3(local.x, local.y, 0.0)
