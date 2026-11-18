extends TestCase
## Road users on lanes: speed limits, stopping at a red light and going on green, queuing, giving
## way to a vehicle and to traffic on priority lanes, waiting at a crossing in use, and taking
## seeded routes. Run on hand-stepped simulations.


func run() -> void:
	_test_light_and_queue()
	_test_give_way()
	_test_crossing()
	_test_routes()


func _lane(s: WorldRunner, from: Vector3, to: Vector3, settings := {}) -> LaneData:
	settings.is_lane = true
	var lane := path(s, from, to, settings)
	if lane.stop_at == INF:
		lane.stop_at = lane.length
	return lane


## The front of a road user driving towards -Z.
func _front(a: AgentState) -> float:
	return a.position().z - a.config.body_size.z * 0.5


func _test_light_and_queue() -> void:
	var s := sim()
	var values := {mode = TrafficLight.Mode.CYCLE, initial = TrafficLight.Light.RED,
		red_time = 1000.0, red_amber_time = 1.0, green_time = 6.0, amber_time = 3.0}
	values.merge(LightLogic.initial(values), true)
	var light := s.world.spawn({light = values})
	var lane := _lane(s, Vector3(0, 0, 100), Vector3(0, 0, -50),
		{speed_limit = 8.0, light = light, stop_at = 80.0})
	var first := road_user(s, lane, {speed = 12.0})
	var second := road_user(s, lane, {speed = 12.0, start_delay = 2.0})
	tick(s, 60)
	expect(is_equal_approx(state_of(s, first).current_speed, 8.0),
		"a road user keeps to its lane's speed limit")
	tick(s, 900)
	var a := state_of(s, first)
	var b := state_of(s, second)
	var line_z := 20.0
	expect(a.reaction == &"waiting_light" and is_zero_approx(a.current_speed)
		and _front(a) > line_z and _front(a) < line_z + 2.0,
		"it stops just before the line at a red light (front at z %.2f)" % _front(a))
	var queue_gap := _front(b) - a.position().z - a.config.body_size.z * 0.5
	expect(b.reaction == &"stopped" and queue_gap > 1.0 and queue_gap < 3.5,
		"the next road user queues behind it (%.2f m back)" % queue_gap)
	s.world.store(Schema.LIGHT).set_value(light, &"state", TrafficLight.Light.GREEN)
	s.world.store(Schema.LIGHT).set_value(light, &"time_in_state", 0.0)
	tick(s, 600)
	expect(state_of(s, first).position().z < line_z - 20.0 and state_of(s, second).position().z < line_z,
		"on green both drive on")
	end_sim(s)


func _test_give_way() -> void:
	# A main lane along -X at z = -1.75, and a side lane coming up to it from +Z.
	var s := sim(Transform3D(Basis.looking_at(Vector3.LEFT), Vector3(3, 0, -1.75)))
	var main := _lane(s, Vector3(60, 0, -1.75), Vector3(-60, 0, -1.75))
	var side := _lane(s, Vector3(1.75, 0, 40), Vector3(1.75, 0, 2),
		{give_way_to = PackedInt64Array([main.id])})
	var waiting := road_user(s, side, {speed = 8.0})
	tick(s, 600)
	var w := state_of(s, waiting)
	expect(w.reaction == &"yielding" and is_zero_approx(w.current_speed),
		"a road user gives way at the line while a vehicle is at the junction")
	place_car(s, Vector3(-40, 0, -30))
	tick(s, 240)
	expect(state_of(s, waiting).is_done(), "and pulls out once the junction is clear")
	end_sim(s)

	s = sim()
	main = _lane(s, Vector3(60, 0, -1.75), Vector3(-60, 0, -1.75))
	side = _lane(s, Vector3(1.75, 0, 30), Vector3(1.75, 0, 2),
		{give_way_to = PackedInt64Array([main.id])})
	# The priority car reaches the junction about 2 s after the side road user reaches its line.
	var priority := road_user(s, main, {speed = 10.0, start_delay = 0.6})
	waiting = road_user(s, side, {speed = 8.0})
	var priority_x := INF
	for i in 900:
		tick(s)
		w = state_of(s, waiting)
		if is_inf(priority_x) and w.progress > 1.0 and _front(w) < 2.0:
			priority_x = state_of(s, priority).position().x
	expect(priority_x < 1.75 - 4.2 * 0.5,
		"a road user waits for a car on the priority lane to clear the junction (it was at x %.2f)"
		% priority_x)
	end_sim(s)


func _test_crossing() -> void:
	var s := sim()
	var events := []
	record_sim(s, events)
	var zone_box := Transform3D(Basis(), Vector3(0, 1.5, 0))
	var half := Vector3(4, 1.5, 2)
	var zone := s.world.spawn({zone = {transform = zone_box, half = half}})
	var walk := path(s, Vector3(-6, 0, 0), Vector3(6, 0, 0))
	var walker := road_user(s, walk, {speed = 1.0, start_delay = 1.0, pedestrian = true,
		body_size = Vector3(0.5, 1.8, 0.5)})
	var lane := _lane(s, Vector3(1.75, 0, 40), Vector3(1.75, 0, -40))
	lane.crossings.append({zone = zone, transform = zone_box, half = half,
		pedestrians = PackedInt64Array([walker]), margin = 1.5, stop = 40.0 - 4.0 - 1.0})
	var car := road_user(s, lane, {speed = 8.0})
	tick(s, 600)
	var c := state_of(s, car)
	var yielded := events.any(func(e: WorldEvent) -> bool:
		return e.kind == &"reacted" and e.entity == car and e.data.kind == &"yielding")
	expect(yielded and is_zero_approx(c.current_speed) and _front(c) > 2.0,
		"a road user waits before a crossing in use (front at z %.2f)" % _front(c))
	tick(s, 900)
	expect(state_of(s, walker).is_done() and state_of(s, car).is_done(),
		"and goes on once the walker is across")
	end_sim(s)


func _routes(seed_value: int, take_right := false) -> String:
	var s := sim()
	var stem := _lane(s, Vector3(0, 0, 20), Vector3(0, 0, 0))
	var left := _lane(s, Vector3(0, 0, 0), Vector3(-20, 0, -20))
	var right := _lane(s, Vector3(0, 0, 0), Vector3(20, 0, -20))
	stem.next = PackedInt64Array([left.id, right.id])
	var settings := {speed = 10.0, route_seed = seed_value}
	if take_right:
		settings.route = PackedInt64Array([right.id])
	var agent := road_user(s, stem, settings)
	tick(s, 240)
	var took: String = "Left" if state_of(s, agent).position().x < -1.0 else "Right"
	end_sim(s)
	return took


func _test_routes() -> void:
	var choices := {}
	for seed_value in 8:
		choices[seed_value] = _routes(seed_value)
	expect(_routes(3) == choices[3], "the same seed takes the same way (%s)" % choices[3])
	expect(choices.values().has("Left") and choices.values().has("Right"),
		"different seeds take different ways %s" % [choices])
	expect(_routes(0, true) == "Right", "a road user takes the way its route names")
