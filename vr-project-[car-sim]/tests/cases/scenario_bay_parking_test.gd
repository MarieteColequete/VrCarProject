extends TestCase
## The bay parking scenario.

const BAY_PARKING := preload("res://scenarios/scenes/bay_parking/bay_parking.tscn")


func run() -> void:
	await _test_bay_parking()


## The free bay of the bay parking scenario, entered from the aisle at x = 3.
const FREE_BAY := Vector3(5.5, 0, -7.5)


func _reverse_into(bay: Vector3) -> Array:
	return [{to = Vector3(0, 0, bay.z), speed = 5.0}, {to = bay, speed = 2.0, reverse = true}]


func _test_bay_parking() -> void:
	var scene := BAY_PARKING.instantiate()
	var into: Vector3 = -scene.get_node("Map/Bays/Bay2").transform.basis.z
	expect(into.is_equal_approx(Vector3.RIGHT), "the car park's bays open onto the aisle")
	scene.free()

	var r := await drive(_reverse_into(FREE_BAY) + [{wait = 3.0}], BAY_PARKING)
	expect_clean(r, "reversing straight into a free bay is clean")

	r = await drive(_reverse_into(Vector3(4.0, 0, -7.5)) + [{wait = 3.0}], BAY_PARKING)
	expect_only(r, &"parking_overhang_serious",
		"stopping half out of the bay is a serious overhang")

	r = await drive(_reverse_into(FREE_BAY) + [{turn = 12.0}, {wait = 3.0}], BAY_PARKING)
	expect(r.reason == &"completed" and r.has_fault(&"parking_misaligned"),
		"ending 12 degrees off is crooked: " + r.summary())

	r = await drive([
		{to = Vector3(0, 0, -7.5), speed = 5.0}, {to = Vector3(2, 0, -7.5), speed = 2.0, reverse = true},
		{to = Vector3(1, 0, -7.5), speed = 2.0}, {to = Vector3(3, 0, -7.5), speed = 2.0, reverse = true},
		{to = Vector3(2, 0, -7.5), speed = 2.0}, {to = FREE_BAY, speed = 2.0, reverse = true},
		{wait = 3.0}], BAY_PARKING)
	expect_only(r, &"parking_too_many_manoeuvres", "five direction changes is too many manoeuvres")

	r = await drive([{wait = 50.0}] + _reverse_into(FREE_BAY) + [{wait = 3.0}], BAY_PARKING)
	expect_only(r, &"parking_too_slow", "taking longer than the limit is too slow")

	r = await drive(_reverse_into(Vector3(5.5, 0, -12.5)) + [{wait = 6.0}], BAY_PARKING)
	expect_only(r, &"parking_reserved",
		"the reserved bay is a fault and does not complete the step", &"aborted")

	r = await drive([{to = Vector3(0, 0, -26), speed = 5.0}, {wait = 6.0}], BAY_PARKING)
	expect_only(r, &"parking_illegal", "settling in the fire lane is illegal parking", &"")

	r = await drive([{to = Vector3(-2.0, 0, -15), speed = 5.0}, {wait = 6.0}], BAY_PARKING)
	expect_only(r, &"parking_illegal", "settling on the yellow line is illegal parking", &"")

	r = await drive([{to = Vector3(0, 0, -15), speed = 5.0}, {wait = 3.0},
		{to = Vector3(0, 0, -7.5), speed = 2.0, reverse = true},
		{to = FREE_BAY, speed = 2.0, reverse = true}, {wait = 3.0}], BAY_PARKING)
	expect_clean(r, "a short stop in the aisle is neither parking nor a fault")
