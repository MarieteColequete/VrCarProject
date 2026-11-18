extends TestCase
## The give way junction scenario.

const GIVE_WAY := preload("res://scenarios/scenes/give_way_junction/give_way_junction.tscn")


func run() -> void:
	await _test_give_way()


## Stops at the give way line, waits, turns right onto the main road, and drives to the goal.
func _turn_right(wait: float, indicate := true) -> Array:
	var legs: Array = []
	if indicate:
		legs.append({indicator = VehicleProbe.Indicator.RIGHT})
	legs += [{to = at(3.0), speed = 8.0}]
	if wait > 0.0:
		legs.append({wait = wait})
	legs += [
		{to = Vector3(2.6, 0, -0.8), speed = 4.0}, {to = Vector3(8, 0, -1.75), speed = 6.0},
		{to = Vector3(45, 0, -1.75), speed = 8.0}]
	return legs


func _test_give_way() -> void:
	var r := await drive(_turn_right(8.5), GIVE_WAY)
	expect_clean(r,
		"waiting for the gap after the stream and turning right while indicating is clean")

	r = await drive(_turn_right(0.0), GIVE_WAY)
	expect_eliminated(r, &"failed_to_give_way",
		"pulling out two seconds ahead of a car on the main road is eliminating")

	r = await drive(_turn_right(22.0), GIVE_WAY)
	expect_only(r, &"undue_hesitation", "waiting long after the road is clear is one minor fault")

	r = await drive(_turn_right(8.5, false), GIVE_WAY)
	expect_only(r, &"no_indicator_turn", "turning without indicating is one minor fault")

	r = await drive([
		{indicator = VehicleProbe.Indicator.LEFT}, {to = at(3.0), speed = 8.0},
		{wait = 8.5}, {to = Vector3(1.0, 0, -3.0), speed = 4.0},
		{to = Vector3(-4, 0, -5.25), speed = 4.0}, {to = Vector3(-12, 0, -5.25), speed = 6.0}], GIVE_WAY)
	expect_only(r, &"wrong_turn", "turning left when the route goes right is a wrong turn", &"")
