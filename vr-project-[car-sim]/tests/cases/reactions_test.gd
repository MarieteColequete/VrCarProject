extends TestCase
## Road users that play by the book until forced to react: following and stopping behind what is
## in the way, resuming the script, forced braking when cut in on, pedestrians waiting for a car,
## and reproducible reactions. Run on a hand-stepped simulation with the car standing in the
## right-hand lane, facing -Z.

const CAR_Z := 50.0


func run() -> void:
	_test_stops_and_resumes()
	_test_forced_braking()
	_test_walker_waits()
	_test_reproducible()


func _with_car() -> WorldRunner:
	return sim(Transform3D(Basis(), at(CAR_Z)))


func _kinds(events: Array, agent: int) -> Array[StringName]:
	var out: Array[StringName] = []
	for e: WorldEvent in events:
		if e.kind == &"reacted" and e.entity == agent:
			out.append(e.data.kind)
	return out


func _test_stops_and_resumes() -> void:
	var s := _with_car()
	var events := []
	record_sim(s, events)
	var agent := road_user(s, path(s, at(90.0), at(-30.0)), {speed = 8.0})
	tick(s, 900)
	var a := state_of(s, agent)
	var gap: float = a.position.z - CAR_Z
	expect(a.reaction == &"stopped" and is_zero_approx(a.current_speed),
		"a road user stops behind the car standing in its lane")
	expect(gap > 4.2 + 0.5 and gap < 4.2 + a.min_gap + 1.0,
		"it stops a little more than its minimum gap behind, without contact (%.2f m apart)" % gap)
	var kinds := _kinds(events, agent)
	expect(kinds.has(&"following") and kinds.back() == &"stopped",
		"it reports following, then stopping: %s" % [kinds])
	place_car(s, Vector3(-20.0, 0, CAR_Z))
	tick(s, 300)
	a = state_of(s, agent)
	kinds = _kinds(events, agent)
	expect(a.reaction.is_empty() and is_equal_approx(a.current_speed, a.speed)
		and kinds.back() == &"resumed", "once the way is clear it resumes its scripted speed")
	end_sim(s)


func _test_forced_braking() -> void:
	var s := sim(Transform3D(Basis(), Vector3(-20.0, 0, CAR_Z)))
	var events := []
	record_sim(s, events)
	var agent := road_user(s, path(s, at(90.0), at(-30.0)), {speed = 12.0})
	tick(s, 120)
	var braked := events.filter(func(e: WorldEvent) -> bool: return e.kind == &"forced_to_brake")
	expect(braked.is_empty() and state_of(s, agent).reaction.is_empty(),
		"on a clear road the road user keeps its script and brakes for nothing")
	# The car cuts in 20 m ahead of its centre, 16 m from its front: room to stop, but only by
	# braking hard.
	var z: float = state_of(s, agent).position.z - 20.0
	place_car(s, Vector3(1.75, 0, z))
	tick(s, 30)
	braked = events.filter(func(e: WorldEvent) -> bool: return e.kind == &"forced_to_brake")
	var a := state_of(s, agent)
	expect(braked.size() == 1 and braked[0].data.cause == car_entity(s)
		and braked[0].data.deceleration > a.hard_brake,
		"a car cutting in close ahead forces it to brake hard, once, naming the car")
	tick(s, 240)
	var gap: float = state_of(s, agent).position.z - z
	expect(gap > 4.2, "and it stops without running into the car (%.2f m apart)" % gap)
	end_sim(s)


func _test_walker_waits() -> void:
	var s := _with_car()
	var walker := road_user(s, path(s, Vector3(-5, 0, CAR_Z), Vector3(9, 0, CAR_Z)),
		{speed = 1.4, pedestrian = true, body_size = Vector3(0.5, 1.8, 0.5), min_gap = 1.0})
	tick(s, 360)
	var w := state_of(s, walker)
	expect(w.reaction == &"stopped" and w.position.x < LANE_X - 0.9,
		"a walker waits before a car standing on its way (at x %.2f)" % w.position.x)
	place_car(s, Vector3(-20.0, 0, CAR_Z))
	tick(s, 600)
	expect((state_of(s, walker).state == AgentTable.State.DONE), "and walks on once the car has gone")
	end_sim(s)


## Positions of three road users queuing behind the car after a fixed number of ticks.
func _queue_positions() -> PackedFloat32Array:
	var s := _with_car()
	var agents := []
	for i in 3:
		agents.append(road_user(s, path(s, at(90.0 + i * 15.0), at(-30.0)), {speed = 9.0 + i}))
	tick(s, 900)
	var out := PackedFloat32Array()
	for agent: int in agents:
		out.append(state_of(s, agent).position.z)
	end_sim(s)
	return out


func _test_reproducible() -> void:
	var first := _queue_positions()
	var second := _queue_positions()
	expect(first == second, "the same traffic reacts the same way every time %s" % [first])
	expect(first[0] < first[1] and first[1] < first[2],
		"road users queue in order behind the car %s" % [first])
