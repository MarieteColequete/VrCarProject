extends TestCase
## The roundabout scenario.

const ROUNDABOUT := preload("res://scenarios/scenes/roundabout/roundabout.tscn")


func run() -> void:
	await _test_roundabout()


## A point on the roundabout's circulating lane, [param degrees] round from the east arm; the
## south entry is at 90, and traffic circulates towards lower angles.
func _ring(degrees: float) -> Vector3:
	return Vector3(cos(deg_to_rad(degrees)), 0, sin(deg_to_rad(degrees))) * 10.0


## Stops at the give way line, waits, enters and circulates, signals right from
## [param signal_at] degrees round when it is not NAN, and leaves by the second exit; or, with
## [param first_exit], by the first.
func _roundabout(wait: float, signal_at := 0.0, first_exit := false) -> Array:
	var legs: Array = [{to = at(16.5), speed = 8.0}]
	if wait > 0.0:
		legs.append({wait = wait})
	var last := 10.0 if first_exit else -80.0
	var angle := 80.0
	while angle >= last:
		if not is_nan(signal_at) and is_equal_approx(angle, signal_at):
			legs.append({indicator = VehicleProbe.Indicator.RIGHT})
		legs.append({to = _ring(angle), speed = 5.0 if angle == 80.0 else 6.0})
		angle -= 10.0
	if first_exit:
		legs += [{to = Vector3(14, 0, 1.75), speed = 6.0}, {to = Vector3(30, 0, 1.75), speed = 8.0}]
	else:
		legs += [{to = at(-14), speed = 6.0}, {to = at(-45), speed = 8.0}]
	return legs


func _test_roundabout() -> void:
	# The circulating cars take the ring at about 6 m/s, so a gap behind them opens about 15 s in.
	var r := await drive(_roundabout(15.0), ROUNDABOUT)
	expect_clean(r,
		"giving way to the circulating traffic and signalling right before the second exit is clean")

	r = await drive(_roundabout(3.0), ROUNDABOUT)
	expect_eliminated(r, &"failed_to_give_way",
		"entering a second ahead of a circulating car is eliminating")

	r = await drive(_roundabout(24.0), ROUNDABOUT)
	expect_only(r, &"undue_hesitation",
		"waiting long after the roundabout is clear is one minor fault")

	r = await drive(_roundabout(15.0, NAN), ROUNDABOUT)
	expect_only(r, &"no_indicator_turn",
		"leaving the roundabout without signalling is one minor fault")

	r = await drive(_roundabout(15.0, 60.0, true), ROUNDABOUT)
	expect_only(r, &"wrong_turn",
		"leaving by the first exit when the route goes straight on is a wrong turn", &"")
