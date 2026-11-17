class_name TrafficSensor
extends RefCounted
## What a road user sees ahead: it sweeps a thin box of the user's width forward along its path,
## in a few segments that follow the curve, and reports the nearest body in the way on the
## vehicle, obstacle, or pedestrian layers. It needs no knowledge of what the body is, so it
## catches anything: the player's car, another road user, a pedestrian, or a parked van.

## Straight segments the look-ahead is split into, so the sweep follows a curved path.
const SEGMENTS := 3


## Something in the way.
class Leader:
	## The body ahead; null when the sweep hit without telling which.
	var body: Node3D
	## Metres from the user's front to the body.
	var gap := INF
	## The body's speed along the user's direction, metres per second; negative when coming
	## towards it.
	var speed := 0.0


var _params := PhysicsShapeQueryParameters3D.new()
var _box := BoxShape3D.new()
var _height := 0.0


func _init(user: CollisionObject3D, size: Vector3) -> void:
	_box.size = Vector3(size.x * 0.9, size.y * 0.8, 0.2)
	_height = size.y * 0.5
	_params.shape = _box
	_params.collision_mask = Layers.VEHICLE | Layers.OBSTACLE | Layers.PEDESTRIAN
	_params.exclude = [user.get_rid()]


## The nearest leader along [param points], the path ahead from the user's front, world space;
## null when the way is clear.
func sense(space: PhysicsDirectSpaceState3D, points: PackedVector3Array) -> Leader:
	var travelled := 0.0
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var length := a.distance_to(b)
		if length < 0.01:
			continue
		var dir := (b - a) / length
		_params.transform = Transform3D(Basis.looking_at(dir, Vector3.UP), a + Vector3.UP * _height)
		_params.motion = b - a
		var result := space.cast_motion(_params)
		if result[1] < 1.0:
			var leader := Leader.new()
			leader.gap = travelled + result[0] * length
			_params.transform.origin += _params.motion * result[1]
			_params.motion = Vector3.ZERO
			var info := space.get_rest_info(_params)
			if not info.is_empty():
				leader.body = instance_from_id(info.collider_id) as Node3D
				leader.speed = speed_of(leader.body, dir)
			return leader
		travelled += length
	return null


## A body's speed along [param direction]: a car's from its probe, a road user's from its
## current speed, and 0 for anything else.
static func speed_of(body: Node3D, direction: Vector3) -> float:
	if body == null:
		return 0.0
	var probe := VehicleProbe.of(body)
	if probe:
		return probe.velocity.dot(direction)
	if body is ScriptedAgent:
		return body.current_speed * body.forward().dot(direction)
	return 0.0
