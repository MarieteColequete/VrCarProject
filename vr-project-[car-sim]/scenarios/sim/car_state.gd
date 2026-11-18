class_name CarState
extends RefCounted
## The player's car in one tick, as a read-only value: where it stands, how it moves, what it
## signals, and its footprint, as [VehicleLogic] derived them. Detection, the rules, and traffic
## read one from the world; the queries below are pure functions of these fields.

var entity := 0
var transform := Transform3D()
var position := Vector3.ZERO
## Horizontal, normalised (Godot's -Z).
var forward := Vector3.FORWARD
var velocity := Vector3.ZERO
## Signed speed along [member forward]; negative when reversing.
var speed := 0.0
var direction := VehicleProbe.Direction.STOPPED
var direction_changes := 0
var stopped_for := 0.0
## Below the stop speed, in any direction.
var stopped := true
## The direction it started moving in this tick, or -1.
var started_moving := -1
var indicator := VehicleProbe.Indicator.UNKNOWN
var handbrake := VehicleProbe.Toggle.UNKNOWN
var look := Vector3.FORWARD
var corners := PackedVector3Array()
var wheels := PackedVector3Array()
var previous_wheels := PackedVector3Array()
var body_length := 4.2
var body_width := 1.8
var hull_size := Vector3(1.9, 1.5, 4.3)
var hull_height := 0.75
var clock := 0.0
var _indicator_seen := VehicleProbe.Indicator.UNKNOWN
var _indicator_since := 0.0


## The car as the world holds it now; null when there is none. Read once while the vehicle's
## columns are unchanged and shared by everyone who asks.
static func read(world: World) -> CarState:
	var s := world.store(Schema.VEHICLE)
	if s == null or s.size() == 0:
		return null
	var cached: Variant = world.memo.get(Schema.VEHICLE)
	if cached != null and cached[0] == s.version:
		return cached[1]
	var car := _read(s)
	world.memo[Schema.VEHICLE] = [s.version, car]
	return car


static func _read(s: ComponentStore) -> CarState:
	var id := s.ids[0]
	var car := CarState.new()
	car.entity = id
	car.transform = s.get_value(id, &"transform")
	car.position = car.transform.origin
	car.forward = s.get_value(id, &"forward")
	car.velocity = s.get_value(id, &"velocity")
	car.speed = s.get_value(id, &"speed")
	car.direction = s.get_value(id, &"direction")
	car.direction_changes = s.get_value(id, &"direction_changes")
	car.stopped_for = s.get_value(id, &"stopped_for")
	car.stopped = s.get_value(id, &"stopped")
	car.started_moving = s.get_value(id, &"started_moving")
	car.indicator = s.get_value(id, &"indicator")
	car.handbrake = s.get_value(id, &"handbrake")
	car.look = s.get_value(id, &"look")
	car.corners = s.get_value(id, &"corners")
	car.wheels = s.get_value(id, &"wheels")
	car.previous_wheels = s.get_value(id, &"previous_wheels")
	car.body_length = s.get_value(id, &"body_length")
	car.body_width = s.get_value(id, &"body_width")
	car.hull_size = s.get_value(id, &"hull_size")
	car.hull_height = s.get_value(id, &"hull_height")
	car.clock = s.get_value(id, &"clock")
	car._indicator_seen = s.get_value(id, &"indicator_seen")
	car._indicator_since = s.get_value(id, &"indicator_since")
	return car


func speed_kmh() -> float:
	return absf(speed) * 3.6


## Come to rest as if parked: stopped with the handbrake on, or for [param settle_time] seconds.
func is_settled(settle_time: float) -> bool:
	if direction != VehicleProbe.Direction.STOPPED:
		return false
	return handbrake == VehicleProbe.Toggle.ON or stopped_for >= settle_time


## Seconds the indicator has shown [param side] without a break; 0 when it shows something else.
func indicator_held_for(side: int) -> float:
	return clock - _indicator_since if indicator == side and _indicator_seen == side else 0.0


## Which side of the car [param dir] points to: left or right.
func side_of(dir: Vector3) -> int:
	return VehicleProbe.Indicator.LEFT if dir.dot(forward.cross(Vector3.UP)) < 0.0 \
		else VehicleProbe.Indicator.RIGHT


## Whether the car faces along [param dir] on the ground rather than against it.
func travels_along(dir: Vector3) -> bool:
	dir.y = 0.0
	return forward.dot(dir) > 0.0


## The driver's look as a signed angle from the car's forward direction, degrees, left positive.
func look_angle() -> float:
	var flat := look
	flat.y = 0.0
	if flat.length() < 0.001:
		return 0.0
	return rad_to_deg(forward.signed_angle_to(flat.normalized(), Vector3.UP))
