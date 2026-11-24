class_name Schema
extends RefCounted
## Every component of the simulation and its columns, declared in one place: what the world can
## hold. A [Bake] fills them from a scenario scene; systems read and write them through deltas.

## The player's car, as the checks and traffic see it: the pose the shell reads from the car each
## tick, and the motion the vehicle system derives from it.
const VEHICLE := &"vehicle"
## A box region of the road: a check's trigger zone, a junction exit, or a no-parking zone.
const ZONE := &"zone"
## A road marking's line, for detection.
const MARKING := &"marking"
const BAY := &"bay"
## Something standing in the way: a parked car or any static box on a judged layer
## ([constant Layers.JUDGED]).
const OBSTACLE := &"obstacle"
const LIGHT := &"light"
## A road user: a scripted car or pedestrian.
const AGENT := &"agent"
## A steady flow of road users onto a lane.
const SOURCE := &"source"
## A check's rule: its parameters, and its state between ticks.
const RULE := &"rule"
## The attempt: its state, clock, faults, and result.
const SESSION := &"session"

## World resources: the marking index, the lanes (entity to [LaneData]), steps, lookup by name,
## and the ways the GPS shows ([GpsRoute]): [code]{step, points}[/code] each, the step's index or
## -1 for the whole attempt, and the points in world space.
const MARKINGS := &"marking_index"
const LANES := &"lanes"
const STEPS := &"steps"
const DEFINITION := &"definition"
const NAMES := &"names"
const ROUTES := &"routes"


static func define(world: World) -> void:
	world.define(VEHICLE, {
		transform = Transform3D(), name = &"",
		velocity = Vector3.ZERO, speed = 0.0, forward = Vector3.FORWARD,
		previous_position = Vector3.ZERO, has_last = false,
		direction = VehicleProbe.Direction.STOPPED, last_moving = VehicleProbe.Direction.STOPPED,
		direction_changes = 0, stopped_for = 0.0, stopped = true,
		# The direction it started moving in this tick, or -1.
		started_moving = -1,
		indicator = VehicleProbe.Indicator.UNKNOWN, indicator_seen = VehicleProbe.Indicator.UNKNOWN,
		indicator_since = 0.0, handbrake = VehicleProbe.Toggle.UNKNOWN,
		look = Vector3.FORWARD, eye = Vector3.ZERO, clock = 0.0,
		# The car's mirrors in its own space: interior, left, right; empty without them.
		mirrors = PackedVector3Array(),
		corners = PackedVector3Array(), wheels = PackedVector3Array(),
		previous_wheels = PackedVector3Array(),
		body_length = 4.2, body_width = 1.8, wheelbase = 2.6, track = 1.55,
		hull_size = Vector3(1.9, 1.5, 4.3), hull_height = 0.75, stop_speed = 0.3,
		# The entities the contact hull touches now.
		touching = PackedInt64Array(),
		# The car's mass, kg, and the impulse the road users it ran into gave it this tick
		# ([Impacts]), N·s, for the shell to give its body.
		mass = 1250.0, impulse = Vector3.ZERO,
	})
	world.define(ZONE, {
		transform = Transform3D(), half = Vector3.ONE, name = &"", kind = &"zone",
		inside = false, entered = false, exited = false,
		# Junction exits: the indicator leaving needs, and whether the route may use it.
		side = VehicleProbe.Indicator.OFF, allowed = true,
		# No-parking zones: the rule's name.
		reason = "",
	})
	world.define(MARKING, {
		kind = RoadMarking.Kind.SOLID, half_width = 0.06, points = PackedVector3Array(), name = &"",
	})
	world.define(BAY, {
		transform = Transform3D(), size = Vector2(2.5, 5.0), facing = ParkingBay.Facing.EITHER,
		reserved = false, occupied = false, name = &"",
	})
	world.define(OBSTACLE, {
		transform = Transform3D(), size = Vector3(1.8, 1.4, 4.2), pedestrian = false, name = &"",
	})
	world.define(LIGHT, {
		name = &"", mode = TrafficLight.Mode.CYCLE, initial = TrafficLight.Light.RED,
		red_time = 6.0, red_amber_time = 1.0, green_time = 6.0, amber_time = 3.0,
		trigger = 0, trigger_delay = 0.0,
		state = TrafficLight.Light.RED, time_in_state = 0.0, holding = false,
		triggered_at = -1.0, clock = 0.0,
	})
	world.define(AGENT, AgentTable.columns())
	world.define(SOURCE, {
		name = &"", lane = 0, count = 5, start_delay = 0.0, min_headway = 3.0, max_headway = 6.0,
		speed = 10.0, route = [], entry_gap = 6.0, colours = [],
		rng_state = 0, clock = 0.0, next_at = 0.0, spawned = 0,
	})
	world.define(RULE, {
		name = &"", params = {}, state = {}, active_steps = PackedInt64Array(),
		order = 0,
		# The script's step and finish, bound once; finish is empty for a rule without one.
		step = Callable(), finish = Callable(),
	})
	world.define(SESSION, {
		state = ExamSession.State.IDLE, elapsed = 0.0, steps_completed = 0, step_count = 0,
		faults = [], last_report = {}, result = null, definition = null,
	})


## The single entity holding [param component], or 0.
static func single(world: World, component: StringName) -> int:
	var s := world.store(component)
	return s.ids[0] if s and s.size() > 0 else 0


## The entity named [param entity_name] that has [param component], or 0.
static func find(world: World, component: StringName, entity_name: StringName) -> int:
	var s := world.store(component)
	if s == null:
		return 0
	var names: Array = s.column(&"name")
	for row in s.size():
		if names[row] == entity_name:
			return s.ids[row]
	return 0
