extends TestCase
## The busy junction: a drive through reactive traffic. Cross traffic queues at its red light, a
## car stuck behind a van changes lanes over the dashed line, a side road car gives way, and cars
## wait at the crossing; the player is judged on the light and the crossing.

const BUSY := preload("res://scenarios/scenes/busy_junction/busy_junction.tscn")

## Every reaction of the attempt, as "<agent> <kind>".
var _log: Array = []


func run() -> void:
	await _test_clean()
	await _test_red_light()
	await _test_reproducible()


func _record(runner: ExamRunner) -> void:
	_log.clear()
	record_reactions(runner, _log)


func _reacted(agent_prefix: String, kind: String) -> bool:
	for line in _log:
		if line.begins_with(agent_prefix) and line.ends_with(" " + kind):
			return true
	return false


## Up to the light, which turns green as the car arrives; over the junction; a stop before the
## crossing while the walker crosses; then on to the end of the road.
func _clean_legs() -> Array:
	return [{to = at(9.0), speed = 8.0}, {to = at(-35.0), speed = 8.0}, {wait = 9.0},
		{to = at(-110.0), speed = 8.0}]


func _test_clean() -> void:
	var r := await drive(_clean_legs(), BUSY, _record)
	expect_clean(r, "driving through the busy junction with the lights and the crossing is clean")
	expect(_reacted("Westbound", "waiting_light") and _reacted("Eastbound", "waiting_light"),
		"cross traffic waits at its red light")
	expect(_reacted("Westbound", "stopped") and _reacted("Eastbound", "stopped"),
		"and queues behind the first car")
	expect(_reacted("Overtaker", "changing_lane"),
		"the car stuck behind the van changes lanes over the dashed line")
	expect(_reacted("SideCar", "yielding"), "the side road car gives way to the main road")
	expect(_reacted("Northbound", "yielding"), "oncoming cars wait at the crossing in use")


func _test_red_light() -> void:
	var r := await drive([{to = at(-35.0), speed = 13.0}], BUSY)
	expect_eliminated(r, &"red_light", "driving through on red is eliminating")


func _test_reproducible() -> void:
	await drive(_clean_legs(), BUSY, _record)
	var first := _log.duplicate()
	await drive(_clean_legs(), BUSY, _record)
	expect(first == _log and first.size() > 20,
		"the same drive meets the same traffic every time (%d reactions)" % first.size())
