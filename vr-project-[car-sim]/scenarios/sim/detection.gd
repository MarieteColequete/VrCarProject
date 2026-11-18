class_name Detection
extends RefCounted
## What the car is in and what it touches, by geometry alone: no physics engine takes part, so
## detection gives the same answer on every run and on any thread.
##
## A zone holds the car while the car's body box (its footprint, as tall as its contact hull)
## overlaps the zone's box, as the body of a car overlaps an area. Contact is the car's contact
## hull, a box slightly larger than the body, overlapping a road user's body or an obstacle's box.


## The zone system: membership of every zone this tick, with entered and exited flags and an
## event for each change.
static func zones(world: World, _dt: float) -> Delta:
	var d := Delta.new()
	var car := CarState.read(world)
	var s := world.store(Schema.ZONE)
	if s == null:
		return d
	for row in s.size():
		var id := s.ids[row]
		var was: bool = s.get_value(id, &"inside")
		var now := car != null and car_in_zone(car, s.get_value(id, &"transform"),
			s.get_value(id, &"half"))
		d.write_all(Schema.ZONE, id, {inside = now, entered = now and not was,
			exited = was and not now})
		if now != was:
			d.emit(WorldEvent.new(&"zone_entered" if now else &"zone_exited", id))
	return d


## Whether the car's body overlaps the box at [param box] with half extents [param half].
static func car_in_zone(car: CarState, box: Transform3D, half: Vector3) -> bool:
	return Geo.body_in_box(car.transform, Vector2(car.body_width, car.body_length),
		car.hull_size.y, box, half)


## The contact system: the bodies the car's hull touches, with a [code]&"contact"[/code] event
## for each one it starts touching.
static func contacts(world: World, _dt: float) -> Delta:
	var d := Delta.new()
	var car := CarState.read(world)
	if car == null:
		return d
	var was: PackedInt64Array = world.get_value(Schema.VEHICLE, car.entity, &"touching")
	var now := PackedInt64Array()
	var hull := Transform3D(car.transform.basis, car.transform.origin)
	var hull_size := Vector2(car.hull_size.x, car.hull_size.z)
	var at := Vector2(car.position.x, car.position.z)
	var reach := Vector2(car.hull_size.x, car.hull_size.z).length() * 0.5
	for body: Array in bodies(world, at, reach):
		if Geo.body_in_box(hull, hull_size, car.hull_height + car.hull_size.y * 0.5, body[1],
				body[2]):
			now.append(body[0])
			if not was.has(body[0]):
				d.emit(WorldEvent.new(&"contact", body[0], {pedestrian = body[3]}))
	d.write(Schema.VEHICLE, car.entity, &"touching", now)
	return d


## The bodies that may stand in the car's way, as [code][id, box transform (centre), half
## extents, pedestrian][/code]: road users and obstacles, sorted by id. With [param reach], only
## those whose box could come within [param reach] metres of [param at] on the ground, a cheap
## test before the exact one.
static func bodies(world: World, at := Vector2.ZERO, reach := INF) -> Array:
	var out := []
	var agents := world.store(Schema.AGENT)
	if agents:
		for id in agents.sorted_ids():
			var state: AgentState = agents.get_value(id, &"state")
			var size := state.config.body_size
			var origin := state.transform.origin
			if Vector2(origin.x, origin.z).distance_to(at) > reach + Vector2(size.x, size.z).length() * 0.5:
				continue
			var centre := state.transform.translated_local(Vector3(0, size.y * 0.5, 0))
			out.append([id, centre, size * 0.5, state.config.pedestrian])
	var obstacles := world.store(Schema.OBSTACLE)
	if obstacles:
		for id in obstacles.sorted_ids():
			var box: Transform3D = obstacles.get_value(id, &"transform")
			var size: Vector3 = obstacles.get_value(id, &"size")
			if Vector2(box.origin.x, box.origin.z).distance_to(at) > reach + Vector2(size.x, size.z).length() * 0.5:
				continue
			out.append([id, box, size * 0.5, obstacles.get_value(id, &"pedestrian")])
	return out
