extends TestCase
## The stop junction scenario.

## Where the car stops at the line.
const STOP_AT := 7.2


func run() -> void:
	await _test_drives()


func _test_drives() -> void:
	var r: ScenarioResult

	r = await drive([
		{to = at(STOP_AT), speed = 8.0}, {wait = 1.0}, {to = at(-24.0), speed = 8.0}])
	expect_clean(r, "clean drive passes with no faults")

	r = await drive([{to = at(-24.0), speed = 8.0}])
	expect(r.reason == &"eliminated" and not r.passed and r.has_fault(&"stop_not_made"),
		"rolling through the stop is eliminating: " + r.summary())

	r = await drive([
		{to = at(14.0), speed = 12.5}, {to = at(STOP_AT), speed = 5.0}, {wait = 1.0},
		{to = at(-24.0), speed = 8.0}])
	expect(r.reason == &"completed" and r.count_tier(&"serious") == 1
		and r.has_fault(&"speeding_serious") and r.faults.size() == 1,
		"45 km/h in the 30 zone is one serious fault: " + r.summary())

	r = await drive([
		{to = at(40.0), speed = 8.0}, {to = at(32.0, -0.5), speed = 8.0},
		{to = at(20.0, -0.5), speed = 8.0}, {to = at(14.0), speed = 8.0},
		{to = at(STOP_AT), speed = 8.0}, {wait = 1.0}, {to = at(-24.0), speed = 8.0}])
	expect(r.reason == &"completed" and r.passed and r.has_fault(&"lane_drift")
		and r.faults.size() == 1,
		"drifting across the centre line is one lane fault: " + r.summary())

	r = await drive([{to = at(40.0), speed = 6.0}, {to = at(27.5, 4.6), speed = 6.0}])
	expect_eliminated(r, &"contact_obstacle", "hitting the parked car is eliminating")

	r = await drive([{to = at(30.0), speed = 6.0}, {to = at(42.0), speed = 5.0}])
	expect_eliminated(r, &"wrong_way", "driving back against the lane is eliminating")
