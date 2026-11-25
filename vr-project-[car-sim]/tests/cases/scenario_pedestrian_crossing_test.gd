extends TestCase
## The pedestrian crossing scenario.

const PEDESTRIAN_CROSSING := preload("res://scenarios/scenes/pedestrian_crossing/pedestrian_crossing.tscn")


func run() -> void:
	_test_in_the_way()
	await _test_pedestrian_crossing()


func _test_in_the_way() -> void:
	# A car at the origin heading north (-z), its path 1 m either side of its middle plus 1 m.
	var car := Vector3.ZERO
	var north := Vector3.FORWARD
	var west := Vector3.LEFT
	var east := Vector3.RIGHT
	expect(CrossingRule.in_the_way(car, north, 2.0, Vector3(1.0, 0, -3), west),
		"a pedestrian in the car's path is in its way")
	expect(CrossingRule.in_the_way(car, north, 2.0, Vector3(5.0, 0, -3), west)
		and CrossingRule.in_the_way(car, north, 2.0, Vector3(-5.0, 0, -3), east),
		"one beside the path and walking toward it is in its way, from either side")
	expect(not CrossingRule.in_the_way(car, north, 2.0, Vector3(-3.0, 0, -3), west)
		and not CrossingRule.in_the_way(car, north, 2.0, Vector3(3.0, 0, -3), east),
		"one who has crossed the path and walks away is not")
	expect(CrossingRule.in_the_way(car, north, 2.0, Vector3(-3.0, 0, -3), north),
		"one not walking across the road counts as in the way")


func _test_pedestrian_crossing() -> void:
	var r := await drive([
		{to = at(5), speed = 8.0}, {wait = 6.0},
		{to = at(-105), speed = 8.0}], PEDESTRIAN_CROSSING)
	expect_clean(r, "waiting at the crossing until the pedestrian is over is clean")

	r = await drive([{to = at(-105), speed = 12.0}], PEDESTRIAN_CROSSING)
	expect(r.reason == &"eliminated" and r.faults.size() == 1
		and r.has_fault(&"crossing_not_given_way"),
		"driving onto the crossing while the pedestrian is still in the car's path is eliminating: "
		+ r.summary())

	r = await drive([{to = at(-105), speed = 8.0}], PEDESTRIAN_CROSSING)
	expect_clean(r, "driving on once the pedestrian has crossed the car's half and walks away is clean")

	r = await drive([
		{to = at(5), speed = 8.0}, {wait = 6.0},
		{to = at(-60), speed = 8.0}, {wait = 3.0},
		{to = at(-105), speed = 8.0}], PEDESTRIAN_CROSSING)
	expect_only(r, &"crossing_stopped_on", "stopping on the empty crossing is one minor fault")
