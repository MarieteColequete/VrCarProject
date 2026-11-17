extends TestCase
## Road users changing lanes round a blocked lane: past a van over a dashed line, not over a solid
## one, and only once the neighbour lane is clear. Built in the stop junction scenario, away from
## its roads, so the scenario's markings decide which lines may be crossed.

const PARKED_CAR := preload("res://scenarios/kit/parked_car.tscn")
## The two lanes, both towards -Z, and the line between them.
const RIGHT_X := 20.0
const LEFT_X := 16.5
const LINE_X := 18.25
const VAN_Z := -10.0


func run() -> void:
	await _test_passes_over_dashed()
	await _test_waits_at_solid()
	await _test_waits_for_clear_lane()


class Road:
	var runner: ExamRunner
	var right: TrafficLane
	var left: TrafficLane
	var agent: ScriptedAgent


func _lane(scenario: Scenario, x: float) -> TrafficLane:
	var lane := TrafficLane.new()
	lane.curve = Curve3D.new()
	lane.curve.add_point(Vector3(x, 0, 60))
	lane.curve.add_point(Vector3(x, 0, -80))
	scenario.add_child(lane)
	return lane


## The two lanes with a van standing in the right one and an agent coming up behind it. The line
## is added before the session starts, so the scenario's marking index includes it.
func _road(line: RoadMarking.Kind) -> Road:
	var road := Road.new()
	road.runner = spawn_runner()
	road.runner.car.input_enabled = false
	var scenario := road.runner.scenario
	var marking := RoadMarking.new()
	marking.kind = line
	marking.curve = Curve3D.new()
	marking.curve.add_point(Vector3(LINE_X, 0, 60))
	marking.curve.add_point(Vector3(LINE_X, 0, -80))
	scenario.get_node("Markings").add_child(marking)
	road.right = _lane(scenario, RIGHT_X)
	road.left = _lane(scenario, LEFT_X)
	road.right.left = road.left
	var van: StaticBody3D = PARKED_CAR.instantiate()
	van.position = Vector3(RIGHT_X, 0.75, VAN_Z)
	scenario.add_child(van)
	road.agent = ScriptedAgent.new()
	road.agent.path = road.right
	road.agent.speed = 8.0
	scenario.add_child(road.agent)
	return road


func _done(road: Road) -> void:
	road.runner.queue_free()
	await process_frame


func _test_passes_over_dashed() -> void:
	var road := _road(RoadMarking.Kind.DASHED)
	var kinds: Array[StringName] = []
	road.agent.reacted.connect(func(kind: StringName, _c: Node3D) -> void: kinds.append(kind))
	await frames(1800)
	expect(kinds.has(&"stopped") and kinds.has(&"changing_lane"),
		"an agent stopped behind a van changes lanes round it: %s" % [kinds])
	expect(road.agent.path == road.left and road.agent.global_position.z < VAN_Z - 10.0
		and absf(road.agent.global_position.x - LEFT_X) < 0.05,
		"it drives on past the van in the neighbour lane (at %s)" % road.agent.global_position)
	await _done(road)


func _test_waits_at_solid() -> void:
	var road := _road(RoadMarking.Kind.SOLID)
	await frames(1800)
	expect(road.agent.path == road.right and road.agent.reaction == &"stopped"
		and road.agent.global_position.z > VAN_Z,
		"behind a solid line it waits behind the van instead")
	await _done(road)


func _test_waits_for_clear_lane() -> void:
	var road := _road(RoadMarking.Kind.DASHED)
	# A second van stands in the neighbour lane beside the agent's waiting place.
	var blocker: StaticBody3D = PARKED_CAR.instantiate()
	blocker.position = Vector3(LEFT_X, 0.75, VAN_Z + 8.0)
	road.runner.scenario.add_child(blocker)
	await frames(1200)
	expect(road.agent.path == road.right and road.agent.reaction == &"stopped",
		"it does not change into a lane with something beside it")
	blocker.queue_free()
	await frames(900)
	expect(road.agent.path == road.left, "and changes once that lane is clear")
	await _done(road)
