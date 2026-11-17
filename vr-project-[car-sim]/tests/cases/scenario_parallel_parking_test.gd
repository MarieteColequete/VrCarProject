extends TestCase
## The parallel parking scenario.

const PARALLEL_PARKING := preload("res://scenarios/scenes/parallel_parking/parallel_parking.tscn")


func run() -> void:
	await _test_parallel_parking()


func _test_parallel_parking() -> void:
	var gap := Vector3(4.65, 0, -21.25)
	var r := await drive([
		{to = Vector3(1.75, 0, gap.z), speed = 6.0}, {to = gap, speed = 1.0, crab = true},
		{wait = 3.0}], PARALLEL_PARKING)
	expect_clean(r, "parking in the gap by the kerb is clean")

	r = await drive([
		{to = Vector3(1.75, 0, gap.z), speed = 6.0}, {to = Vector3(3.9, 0, gap.z), speed = 1.0, crab = true},
		{wait = 3.0}], PARALLEL_PARKING)
	expect_only(r, &"parking_overhang_serious",
		"stopping with half the car in the road is a serious overhang")

	r = await drive([
		{to = at(-8), speed = 6.0}, {to = Vector3(4.65, 0, -8), speed = 1.0, crab = true},
		{wait = 6.0}], PARALLEL_PARKING)
	expect_only(r, &"parking_illegal", "parking along the no-parking line is illegal", &"")
