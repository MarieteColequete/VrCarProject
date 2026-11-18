extends TestCase
## Road users changing lanes round a blocked lane: past a van over a dashed line, not over a solid
## one, and only once the neighbour lane is clear. The marking between the lanes decides which
## lines may be crossed. Run on hand-stepped simulations.

## The two lanes, both towards -Z, and the line between them.
const RIGHT_X := 20.0
const LEFT_X := 16.5
const LINE_X := 18.25
const VAN_Z := -10.0
const VAN := Vector3(1.8, 1.4, 4.2)


func run() -> void:
	_test_passes_over_dashed()
	_test_waits_at_solid()
	_test_waits_for_clear_lane()


class Road:
	var sim: WorldRunner
	var right: LaneData
	var left: LaneData
	var agent := 0
	var events := []


func _road(owner: TestCase, line: RoadMarking.Kind) -> Road:
	var road := Road.new()
	road.sim = owner.sim()
	var world := road.sim.world
	var points := PackedVector3Array([Vector3(LINE_X, 0, 60), Vector3(LINE_X, 0, -80)])
	var marking := world.spawn({marking = {kind = line, half_width = 0.06, points = points}})
	(world.resources[Schema.MARKINGS] as MarkingIndex).add(marking, line, 0.06, points)
	road.right = owner.path(road.sim, Vector3(RIGHT_X, 0, 60), Vector3(RIGHT_X, 0, -80),
		{is_lane = true})
	road.left = owner.path(road.sim, Vector3(LEFT_X, 0, 60), Vector3(LEFT_X, 0, -80),
		{is_lane = true})
	road.right.left = road.left.id
	world.spawn({obstacle = {transform = Transform3D(Basis(), Vector3(RIGHT_X, 0.75, VAN_Z)),
		size = VAN, name = &"Van"}})
	owner.record_sim(road.sim, road.events)
	road.agent = owner.road_user(road.sim, road.right, {speed = 8.0})
	return road


func _test_passes_over_dashed() -> void:
	var road := _road(self, RoadMarking.Kind.DASHED)
	tick(road.sim, 1800)
	var kinds := road.events.filter(func(e: WorldEvent) -> bool: return e.kind == &"reacted") \
		.map(func(e: WorldEvent) -> StringName: return e.data.kind)
	expect(kinds.has(&"stopped") and kinds.has(&"changing_lane"),
		"a road user stopped behind a van changes lanes round it: %s" % [kinds])
	var a := state_of(road.sim, road.agent)
	expect(a.lane == road.left.id and a.position().z < VAN_Z - 10.0
		and absf(a.position().x - LEFT_X) < 0.05,
		"it drives on past the van in the neighbour lane (at %s)" % a.position())
	end_sim(road.sim)


func _test_waits_at_solid() -> void:
	var road := _road(self, RoadMarking.Kind.SOLID)
	tick(road.sim, 1800)
	var a := state_of(road.sim, road.agent)
	expect(a.lane == road.right.id and a.reaction == &"stopped" and a.position().z > VAN_Z,
		"behind a solid line it waits behind the van instead")
	end_sim(road.sim)


func _test_waits_for_clear_lane() -> void:
	var road := _road(self, RoadMarking.Kind.DASHED)
	# A second van stands in the neighbour lane beside the road user's waiting place.
	var blocker := road.sim.world.spawn({obstacle = {transform = Transform3D(Basis(),
		Vector3(LEFT_X, 0.75, VAN_Z + 8.0)), size = VAN, name = &"Blocker"}})
	tick(road.sim, 1200)
	var a := state_of(road.sim, road.agent)
	expect(a.lane == road.right.id and a.reaction == &"stopped",
		"it does not change into a lane with something beside it")
	road.sim.world.despawn(blocker)
	tick(road.sim, 900)
	expect(state_of(road.sim, road.agent).lane == road.left.id,
		"and changes once that lane is clear")
	end_sim(road.sim)
