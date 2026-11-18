extends TestCase
## The lane change and overtaking scenario.

const LANE_CHANGE := preload("res://scenarios/scenes/lane_change_overtake/lane_change_overtake.tscn")


func run() -> void:
	await _test_lane_change()


func _overtake(mirror := true, shoulder := true) -> Array:
	var left := VehicleProbe.Indicator.LEFT
	var right := VehicleProbe.Indicator.RIGHT
	var legs: Array = [{indicator = left}, {to = at(60), speed = 12.0}]
	if mirror:
		legs.append({look = 35.0})
	legs.append({to = at(52), speed = 12.0})
	if shoulder:
		legs.append({look = 110.0})
	legs += [
		{to = at(50), speed = 12.0}, {look = 0.0},
		{to = Vector3(-1.75, 0, 38), speed = 12.0}, {to = Vector3(-1.75, 0, 20), speed = 12.0},
		{indicator = right}, {look = -35.0}, {to = Vector3(-1.75, 0, 14), speed = 12.0},
		{look = -110.0}, {to = Vector3(-1.75, 0, 8), speed = 12.0}, {look = 0.0},
		{to = at(-6), speed = 12.0}, {indicator = VehicleProbe.Indicator.OFF},
		{to = at(-195), speed = 12.0}]
	return legs


func _test_lane_change() -> void:
	var gaze := GazeCheck.new()
	expect(gaze.require_shoulder and gaze.mirror_angle < gaze.shoulder_angle,
		"lane changes need a mirror look and a wider shoulder look by default")
	gaze.free()

	var r := await drive([{to = at(-195), speed = 4.0}], LANE_CHANGE)
	expect_clean(r, "following the slow vehicle at a distance is clean")

	r = await drive(_overtake(), LANE_CHANGE)
	expect_clean(r,
		"overtaking on the dashed line with mirror, shoulder, and indicator both ways is clean")

	r = await drive(_overtake(false, true), LANE_CHANGE)
	expect_only(r, &"no_mirror_check", "pulling out without the mirror is one minor fault")

	r = await drive(_overtake(true, false), LANE_CHANGE)
	expect_only(r, &"no_shoulder_check",
		"pulling out without the shoulder check is one minor fault")

	r = await drive([
		{to = at(35.3), speed = 12.0}, {to = at(-4.7), speed = 4.0}],
		LANE_CHANGE)
	expect_only(r, &"following_too_close",
		"sitting 1.5 s behind the slow vehicle is following too closely", &"")
