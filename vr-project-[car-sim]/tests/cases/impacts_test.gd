extends TestCase
## Crashes between the player's car and road users' cars ([Impacts]), on hand-stepped
## simulations: a road user run into is knocked on and, hit hard, crashes and brakes to a halt,
## the car takes the opposite knock, a touch while parting gives none, and the same crash comes
## out the same every run.


func run() -> void:
	_test_rear_end()
	_test_parting()
	_test_repeats()


## A road user driving its lane at 5 m/s, and the car driving into its back at [param speed], as
## the shell would move it, until the knock: [runner, road user, events, the car's impulse].
func _crash(speed: float) -> Array:
	var runner := sim(Transform3D(Basis(), Vector3(0, 0, 6.0)))
	var lane := path(runner, Vector3(0, 0, 0), Vector3(0, 0, -200), {is_lane = true})
	var agent := road_user(runner, lane, {speed = 5.0, reactive = false})
	var events := []
	record_sim(runner, events)
	tick(runner)
	var z := 6.0
	var knocked := Vector3.ZERO
	for i in 60:
		z -= speed / 60.0
		place_car(runner, Vector3(0, 0, z))
		tick(runner)
		var push: Vector3 = runner.world.store(Schema.VEHICLE).get_value(
			car_entity(runner), &"impulse")
		if push != Vector3.ZERO:
			knocked = push
			break
	return [runner, agent, events, knocked]


func _test_rear_end() -> void:
	var result := _crash(25.0)
	var runner: WorldRunner = result[0]
	var a := state_of(runner, result[1])
	var knocked: Vector3 = result[3]
	expect(knocked.z > 1000.0, "run into from behind, the road user pushes the car back: %s"
		% knocked)
	expect(a.current_speed > 8.0, "and is knocked on, faster than it drove: %.1f m/s"
		% a.current_speed)
	expect(a.crashed, "hit that hard, it crashes")
	var crashes: Array = (result[2] as Array).filter(func(e: WorldEvent) -> bool:
		return e.kind == &"crashed")
	expect(crashes.size() == 1, "once")
	tick(runner, 300)
	a = state_of(runner, result[1])
	expect(is_zero_approx(a.current_speed), "and brakes to a halt: %.2f m/s" % a.current_speed)
	end_sim(runner)


func _test_parting() -> void:
	var runner := sim(Transform3D(Basis(), Vector3(0, 0, 3.0)))
	var lane := path(runner, Vector3(0, 0, 0), Vector3(0, 0, -200), {is_lane = true})
	var agent := road_user(runner, lane, {speed = 10.0, reactive = false})
	tick(runner, 2)
	var a := state_of(runner, agent)
	expect(not a.crashed and is_equal_approx(a.current_speed, 10.0),
		"overlapping while it drives away from the car, it is not knocked")
	end_sim(runner)


func _test_repeats() -> void:
	var first := _crash(20.0)
	var second := _crash(20.0)
	var a := state_of(first[0], first[1])
	var b := state_of(second[0], second[1])
	expect(a.current_speed == b.current_speed and a.yaw_rate == b.yaw_rate
		and first[3] == second[3], "the same crash comes out the same")
	end_sim(first[0])
	end_sim(second[0])
