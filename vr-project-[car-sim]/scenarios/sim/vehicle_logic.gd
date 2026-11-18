class_name VehicleLogic
extends RefCounted
## The player's car's motion, derived each tick from its pose alone, so it works with any car
## implementation: velocity and signed speed from the last position, the direction of travel and
## the manoeuvre count of parking, how long it has been stopped, how long the indicator has shown
## its side, and the footprint (body corners and wheel contact points) checks judge lines and
## parking on.


## The vehicle system: reads the pose the shell wrote this tick and returns the derived motion.
static func run(world: World, dt: float) -> Delta:
	var d := Delta.new()
	var s := world.store(Schema.VEHICLE)
	if s == null:
		return d
	for row in s.size():
		var id := s.ids[row]
		d.write_all(Schema.VEHICLE, id, step(_row(s, id), dt))
	return d


## The next motion of a vehicle row [param v] (column name to value), as the columns to write.
static func step(v: Dictionary, dt: float) -> Dictionary:
	var out := {}
	var t: Transform3D = v.transform
	var clock: float = v.clock + dt
	out.clock = clock
	if v.indicator != v.indicator_seen:
		out.indicator_seen = v.indicator
		out.indicator_since = clock
	var f := -t.basis.z
	f.y = 0.0
	var forward := f.normalized()
	out.forward = forward
	var velocity: Vector3 = v.velocity
	var speed: float = v.speed
	if v.has_last and dt > 0.0:
		velocity = (t.origin - v.previous_position) / dt
		speed = velocity.dot(forward)
	out.velocity = velocity
	out.speed = speed
	out.previous_position = t.origin
	out.has_last = true
	var stopped: bool = Vector2(velocity.x, velocity.z).length() < v.stop_speed
	out.stopped = stopped
	var now := VehicleProbe.Direction.STOPPED
	if not stopped:
		now = VehicleProbe.Direction.REVERSE if speed < 0.0 else VehicleProbe.Direction.FORWARD
	out.started_moving = -1
	out.direction = now
	if now != v.direction and now != VehicleProbe.Direction.STOPPED:
		out.started_moving = now
		if v.last_moving != VehicleProbe.Direction.STOPPED and v.last_moving != now:
			out.direction_changes = v.direction_changes + 1
		out.last_moving = now
	out.stopped_for = v.stopped_for + dt if now == VehicleProbe.Direction.STOPPED else 0.0
	var wheels := Geo.ground_rect(t, v.track, v.wheelbase)
	var previous: PackedVector3Array = v.wheels
	out.previous_wheels = previous if not previous.is_empty() else wheels
	out.wheels = wheels
	out.corners = Geo.ground_rect(t, v.body_width, v.body_length)
	return out


static func _row(s: ComponentStore, id: int) -> Dictionary:
	var row := {}
	for column: StringName in s.columns:
		row[column] = s.get_value(id, column)
	return row
