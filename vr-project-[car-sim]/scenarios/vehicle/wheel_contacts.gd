class_name WheelContacts
extends RefCounted
## Where the player's car's tyres meet the road: each wheel's heading and side on the ground's
## plane under it, from the body's facing and the wheel's road angle ([Steering]), and how its
## contact patch moves in that frame. Geometry only, from the body's motion. Node free: it keeps
## its own state from step to step and reads nothing but its arguments.

## Each wheel's heading and side (to its left) on the ground's plane, unit vectors.
var headings := PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
var sides := PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])
## How each contact patch moves along its wheel's heading and to its side, m/s.
var along := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
var across := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])


## Measures the four contacts: the body facing [param forward] with [param up] its up, moving at
## [param velocity] and turning at [param spin] (rad/s) about its centre of mass at [param centre];
## each wheel at its road angle [param angles] (radians, left positive) touching at
## [param contacts] on ground with normal [param normals].
func measure(forward: Vector3, up: Vector3, velocity: Vector3, spin: Vector3, centre: Vector3,
		angles: PackedFloat64Array, contacts: PackedVector3Array,
		normals: PackedVector3Array) -> void:
	for i in 4:
		var n := normals[i]
		var aim := forward.rotated(up, angles[i]) if angles[i] != 0.0 else forward
		var flat := aim - n * aim.dot(n)
		var heading := flat.normalized() if flat.length_squared() > 0.0001 else aim
		var side := n.cross(heading)
		headings[i] = heading
		sides[i] = side
		var moving := velocity + spin.cross(contacts[i] - centre)
		along[i] = moving.dot(heading)
		across[i] = moving.dot(side)
