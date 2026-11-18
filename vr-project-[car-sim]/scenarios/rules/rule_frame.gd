class_name RuleFrame
extends RefCounted
## One tick as the rules see it, read-only: the car, the clock, the step, the markings the wheels
## crossed, and queries on zones, bays, lights, road users, and the tick's events. [ExamLogic]
## builds one per tick and hands it to every rule, so all rules judge the same moment.

var car: CarState
var dt := 0.0
## Seconds since the attempt started running.
var elapsed := 0.0
## Index of the current step; -1 when the scenario has none or they are all done.
var current_step := -1
## The markings the car's wheels crossed this tick.
var crossings: Array[MarkingHit] = []
var markings: MarkingIndex
## The road users, read as they stand: the view the tick shares ([method AgentTable.read]).
var agents: AgentTable
var lanes := {}
## The events of this tick so far: what traffic, lights, zones, and contacts did.
var events: Array[WorldEvent] = []

var _world: World


static func build(world: World, dt: float, elapsed: float, current_step: int) -> RuleFrame:
	var f := RuleFrame.new()
	f._world = world
	f.car = CarState.read(world)
	f.dt = dt
	f.elapsed = elapsed
	f.current_step = current_step
	f.markings = world.resources.get(Schema.MARKINGS)
	f.agents = AgentTable.read(world)
	f.lanes = world.resources.get(Schema.LANES, {})
	f.events = world.events.duplicate()
	if f.car and f.markings:
		for i in f.car.wheels.size():
			f.crossings.append_array(f.markings.crossings(f.car.previous_wheels[i], f.car.wheels[i]))
	return f


func inside(zone: int) -> bool:
	return zone != 0 and _world.has(Schema.ZONE, zone) and _world.get_value(Schema.ZONE, zone, &"inside")


func entered(zone: int) -> bool:
	return zone != 0 and _world.has(Schema.ZONE, zone) \
		and _world.get_value(Schema.ZONE, zone, &"entered")


func exited(zone: int) -> bool:
	return zone != 0 and _world.has(Schema.ZONE, zone) and _world.get_value(Schema.ZONE, zone, &"exited")


func zone_value(zone: int, column: StringName) -> Variant:
	return _world.get_value(Schema.ZONE, zone, column)


## Whether [param point] lies in [param zone]'s box, grown by [param margin] on the ground.
func zone_has_point(zone: int, point: Vector3, margin := 0.0) -> bool:
	if zone == 0 or not _world.has(Schema.ZONE, zone):
		return false
	return Geo.point_in_box(zone_value(zone, &"transform"), zone_value(zone, &"half"), point, margin)


## The zones of [param kind], such as [code]&"no_parking"[/code].
func zones_of(kind: StringName) -> PackedInt64Array:
	var out := PackedInt64Array()
	var s := _world.store(Schema.ZONE)
	for id in s.sorted_ids():
		if s.get_value(id, &"kind") == kind:
			out.append(id)
	return out


func bay(id: int) -> Dictionary:
	var s := _world.store(Schema.BAY)
	var out := {id = id}
	for column: StringName in s.columns:
		out[column] = s.get_value(id, column)
	return out


## The bay holding [param point], among [param among] or every bay when it is empty; empty when
## none does.
func bay_at(point: Vector3, among := PackedInt64Array()) -> Dictionary:
	var s := _world.store(Schema.BAY)
	if s == null:
		return {}
	for id in (among if not among.is_empty() else s.sorted_ids()):
		if not s.has(id):
			continue
		if Geo.overhang(s.get_value(id, &"transform"), s.get_value(id, &"size"),
				PackedVector3Array([point])) <= 0.0:
			return bay(id)
	return {}


func light_state(light: int) -> int:
	return _world.get_value(Schema.LIGHT, light, &"state") if _world.has(Schema.LIGHT, light) else -1


## The phase [param light] changed to this tick, or -1.
func light_changed(light: int) -> int:
	for event in events:
		if event.kind == &"light_changed" and event.entity == light:
			return event.data.state
	return -1


## The row of road user [param id] in [member agents], or -1.
func agent(id: int) -> int:
	return agents.row_of(id)


func events_of(kind: StringName) -> Array[WorldEvent]:
	var out: Array[WorldEvent] = []
	for event in events:
		if event.kind == kind:
			out.append(event)
	return out
