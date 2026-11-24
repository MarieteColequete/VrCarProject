extends TestCase
## Making other road users react: pulling into a lane so close in front of a road user that it
## must brake hard is a fault; joining with a fair gap is not. Driven on the lane change scenario's
## long straight road, whose end behind the car is open, with a car coming up its lane from behind.

const LANE_CHANGE := preload("res://scenarios/scenes/lane_change_overtake/lane_change_overtake.tscn")
## Where the car waits beside the lane before joining it, and where it joins: beside its spawn.
const KERB := Vector3(4.6, 0, 80)
const JOIN := Vector3(1.75, 0, 80)


func run() -> void:
	await _test_cut_in()
	await _test_fair_gap()


## Adds a car to the scenario that comes up the lane from behind at 12 m/s after [param delay].
func _add_follower(delay: float) -> Callable:
	return func(runner: ExamRunner) -> void:
		var lane := Path3D.new()
		lane.curve = Curve3D.new()
		lane.curve.add_point(at(144.0))
		lane.curve.add_point(at(-6.0))
		runner.scenario.add_child(lane)
		var follower := ScriptedAgent.new()
		follower.name = "Follower"
		follower.path = lane
		follower.speed = 12.0
		follower.start_delay = delay
		runner.add_road_user(follower)


## Moves to the kerb, waits [param wait] seconds, then pulls straight into the lane.
func _join(wait: float) -> Array:
	return [{to = KERB, speed = 3.0, crab = true}, {wait = wait},
		{to = JOIN, speed = 100.0, crab = true}, {wait = 6.0}]


func _test_cut_in() -> void:
	# The follower is about 17 m behind when the car pulls in: it can stop, but only hard.
	var r := await drive(_join(2.6), LANE_CHANGE, _add_follower(0.0))
	expect(r.has_fault(&"caused_hard_braking") and not r.has_fault(&"contact_obstacle"),
		_with("pulling in close in front of a car is a fault, and the car still stops short", r))


func _test_fair_gap() -> void:
	# The follower sets off well after the car has joined, and slows to a stop behind it calmly.
	var reaction := [&""]
	var r := await drive(_join(2.6) + [{wait = 6.0}], LANE_CHANGE, _add_follower(6.0),
		func(runner: ExamRunner) -> void:
			reaction[0] = agent_state(runner, &"Follower").reaction)
	expect(reaction[0] == &"stopped" and not r.has_fault(&"caused_hard_braking")
		and not r.has_fault(&"contact_obstacle"),
		_with("joining with a fair gap makes the car behind stop calmly, and nobody brake hard", r))
