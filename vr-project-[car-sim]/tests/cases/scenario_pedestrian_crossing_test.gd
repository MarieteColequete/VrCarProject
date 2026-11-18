extends TestCase
## The pedestrian crossing scenario.

const PEDESTRIAN_CROSSING := preload("res://scenarios/scenes/pedestrian_crossing/pedestrian_crossing.tscn")


func run() -> void:
	await _test_pedestrian_crossing()


func _test_pedestrian_crossing() -> void:
	var r := await drive([
		{to = at(5), speed = 8.0}, {wait = 6.0},
		{to = at(-105), speed = 8.0}], PEDESTRIAN_CROSSING)
	expect_clean(r, "waiting at the crossing until the pedestrian is over is clean")

	r = await drive([{to = at(-105), speed = 8.0}], PEDESTRIAN_CROSSING)
	expect(r.reason == &"eliminated" and r.faults.size() == 1
		and r.has_fault(&"crossing_not_given_way"),
		"driving onto the crossing while the pedestrian is on it is eliminating: " + r.summary())

	r = await drive([
		{to = at(5), speed = 8.0}, {wait = 6.0},
		{to = at(-60), speed = 8.0}, {wait = 3.0},
		{to = at(-105), speed = 8.0}], PEDESTRIAN_CROSSING)
	expect_only(r, &"crossing_stopped_on", "stopping on the empty crossing is one minor fault")
