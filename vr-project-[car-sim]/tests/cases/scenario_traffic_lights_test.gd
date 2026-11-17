extends TestCase
## The traffic lights scenario.

const TRAFFIC_LIGHTS := preload("res://scenarios/scenes/traffic_lights/traffic_lights.tscn")


func run() -> void:
	await _test_traffic_lights()


func _test_traffic_lights() -> void:
	var check := TrafficLightCheck.new()
	expect(is_equal_approx(check.stopping_distance(10.0), 10.0 * 0.75 + 100.0 / 8.0),
		"stopping distance is reaction distance plus braking distance")
	check.free()

	var r := await drive([
		{to = at(52), speed = 13.5}, {to = at(2.7), speed = 8.0},
		{wait = 12.0}, {to = at(-155), speed = 13.5}], TRAFFIC_LIGHTS)
	expect_clean(r,
		"stopping for the first light and going on amber at the second, too close to stop, is clean")

	r = await drive([{to = at(-155), speed = 8.0}], TRAFFIC_LIGHTS)
	expect_eliminated(r, &"red_light", "reaching the first line after it turned red is eliminating")

	r = await drive([{to = at(-155), speed = 13.5}], TRAFFIC_LIGHTS)
	expect_only(r, &"amber_light",
		"crossing on an amber there was room to stop for is one serious fault")
