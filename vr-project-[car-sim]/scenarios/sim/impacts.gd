class_name Impacts
extends RefCounted
## Crashes between the player's car and road users' cars, by geometry, the same for the same car
## state: the car's body and a road user's body overlapping on the ground while closing on each
## other trade an impulse along the side they meet across, shared by their masses, a little elastic.
## The road user's share changes its speeds (forward, sideways, and its yaw, by where it was
## struck); hit hard, it crashes ([code]crashed[/code]): it stops driving its lane and brakes to a
## halt where the knock leaves it, and the road users behind treat it as an obstacle to go round.
## The car's share goes to the vehicle's [code]impulse[/code], which the shell gives the car's body.
## The physics engine does not meet road users' cars at all ([TrafficView] exempts the player's
## body), so this is the one place the two touch. Walkers stay with the engine and the contact
## rules.

## How elastic a knock is: 0 the two move on together, 1 they bounce apart fully.
const RESTITUTION := 0.2
## The change of speed, m/s, past which a road user crashes.
const CRASH_SPEED := 2.0


## The impacts system: a knock for every road user's car the player's car runs into this tick.
static func run(world: World, _dt: float) -> Delta:
	var d := Delta.new()
	var car := CarState.read(world)
	var agents := world.store(Schema.AGENT)
	var vehicles := world.store(Schema.VEHICLE)
	if car == null or agents == null or vehicles == null:
		return d
	var push := Vector3.ZERO
	var states: PackedInt64Array = agents.column(&"state")
	var walkers: PackedByteArray = agents.column(&"pedestrian")
	var positions: PackedVector3Array = agents.column(&"position")
	var facings: PackedVector3Array = agents.column(&"facing")
	var sizes: PackedVector3Array = agents.column(&"body_size")
	var speeds: PackedFloat64Array = agents.column(&"current_speed")
	var sides: PackedFloat64Array = agents.column(&"side_speed")
	var yaws: PackedFloat64Array = agents.column(&"yaw_rate")
	var specs: PackedInt64Array = agents.column(&"spec")
	var crashed: PackedByteArray = agents.column(&"crashed")
	var packed := TrafficSpecs.all()
	var mine := car.mass
	var at := Vector2(car.position.x, car.position.z)
	var along := Vector2(car.forward.x, car.forward.z).normalized()
	var flat_velocity := Vector2(car.velocity.x, car.velocity.z)
	for row in agents.size():
		if walkers[row] or specs[row] < 0:
			continue
		var f := Vector2(facings[row].x, facings[row].z)
		if f.length() < 0.001:
			continue
		f = f.normalized()
		var centre := Vector2(positions[row].x, positions[row].z)
		var normal := Geo.box_contact_normal(at, along, car.body_length * 0.5,
			car.body_width * 0.5, centre, f, sizes[row].z * 0.5, sizes[row].x * 0.5)
		if normal == Vector2.ZERO:
			continue
		var left := Vector2(f.y, -f.x)
		var theirs := f * speeds[row] + left * sides[row]
		var closing := (theirs - flat_velocity).dot(normal)
		if closing >= 0.0:
			continue
		var spec: PackedFloat64Array = packed[specs[row]]
		var mass := spec[CarSpec.MASS]
		var j := -(1.0 + RESTITUTION) * closing / (1.0 / mine + 1.0 / mass)
		var kick := normal * (j / mass)
		var after := theirs + kick
		# Struck off its centre, it turns: the knock lands about halfway between the two centres.
		var arm := (at - centre) * 0.5
		var turn := (arm.y * normal.x - arm.x * normal.y) * j / spec[CarSpec.YAW_INERTIA]
		var id := agents.ids[row]
		d.write(Schema.AGENT, id, &"current_speed", after.dot(f))
		d.write(Schema.AGENT, id, &"side_speed", after.dot(left))
		d.write(Schema.AGENT, id, &"yaw_rate", yaws[row] + turn)
		if kick.length() > CRASH_SPEED and not crashed[row]:
			d.write(Schema.AGENT, id, &"crashed", true)
			if states[row] != AgentTable.State.MOVING:
				d.write(Schema.AGENT, id, &"state", AgentTable.State.MOVING)
			d.emit(WorldEvent.new(&"crashed", id, {by = car.entity, change = kick.length()}))
		var back := -normal * j
		push += Vector3(back.x, 0.0, back.y)
	var was: Vector3 = vehicles.get_value(car.entity, &"impulse")
	if push != was:
		d.write(Schema.VEHICLE, car.entity, &"impulse", push)
	return d

