class_name TestCase
extends RefCounted
## Base of every test case under [code]res://tests/cases/[/code]. A case overrides [method run],
## awaits frames through [member physics_frame] and [member process_frame], adds nodes under
## [member root], and asserts with the [code]expect[/code] helpers, which count passes and
## failures for the runner.

const RUNNER := preload("res://scenarios/scenes/exam_runner.tscn")
const STOP_JUNCTION := preload("res://scenarios/scenes/stop_junction/stop_junction.tscn")
const FAULTS := "res://scenarios/data/faults/%s.tres"
## The centre of the right-hand lane; scenarios are built with the car driving towards -Z in it.
const LANE_X := 1.75

var passed := 0
var failed := 0
var tree: SceneTree
var root: Window
var physics_frame: Signal
var process_frame: Signal


func setup(p_tree: SceneTree) -> void:
	tree = p_tree
	root = tree.root
	physics_frame = tree.physics_frame
	process_frame = tree.process_frame


## The case's tests; awaited by the runner.
func run() -> void:
	pass


func expect(condition: bool, what: String) -> void:
	if condition:
		passed += 1
		if OS.has_environment("TESTS_VERBOSE"):
			print("ok: ", what)
	else:
		failed += 1
		printerr("FAIL: ", what)


## The attempt completed and passed with no faults.
func expect_clean(r: ScenarioResult, what: String) -> void:
	expect(r.reason == &"completed" and r.passed and r.faults.is_empty(), _with(what, r))


## [param id] is the attempt's only fault, and it ended for [param reason]; an empty reason
## accepts any ending.
func expect_only(r: ScenarioResult, id: StringName, what: String, reason := &"completed") -> void:
	expect((reason.is_empty() or r.reason == reason) and r.faults.size() == 1 and r.has_fault(id),
		_with(what, r))


## The attempt was eliminated, with [param id] among its faults.
func expect_eliminated(r: ScenarioResult, id: StringName, what: String) -> void:
	expect(r.reason == &"eliminated" and r.has_fault(id), _with(what, r))


## A point in the right-hand lane, [param z] along it, or [param x] across.
func at(z: float, x := LANE_X) -> Vector3:
	return Vector3(x, 0.0, z)


func frames(n: int) -> void:
	for i in n:
		await physics_frame


## Drives a scenario's car along [param legs] and returns the result.
## Legs: {to: Vector3, speed: m/s} moves in a straight line, facing the target, or facing away
## from it with reverse = true, or keeping its heading with crab = true; {wait: s} stays put;
## {turn: degrees} turns in place (positive is left); {indicator: Indicator} sets the probe's
## indicator; {look: degrees} turns the driver's view to that angle (positive is left).
## [param on_spawn] is called with the runner once the car is placed, and [param on_end] just
## before it is freed. Without a scenario, the stop junction is driven.
func drive(legs: Array, scenario: PackedScene = null, on_spawn := Callable(),
		on_end := Callable()) -> ScenarioResult:
	var runner: ExamRunner = RUNNER.instantiate()
	runner.print_results = false
	runner.scenario_scene = scenario if scenario else STOP_JUNCTION
	root.add_child(runner)
	if on_spawn.is_valid():
		on_spawn.call(runner)
	var car: Node3D = runner.car
	car.input_enabled = false
	var session := runner.session
	var dt := 1.0 / Engine.physics_ticks_per_second
	await physics_frame
	for leg: Dictionary in legs:
		if leg.has("indicator"):
			VehicleProbe.of(car).indicator = leg.indicator
			continue
		if leg.has("look"):
			car.driver_view.reset_look()
			car.driver_view.turn(deg_to_rad(leg.look), 0.0)
			continue
		if leg.has("turn"):
			car.rotate_y(deg_to_rad(leg.turn))
			await physics_frame
			continue
		if leg.has("wait"):
			var waited := 0.0
			while waited < leg.wait and session.is_running():
				await physics_frame
				waited += dt
			continue
		var target: Vector3 = leg.to
		while session.is_running() and car.global_position.distance_to(target) > 0.001:
			var pos := car.global_position
			var dir := target - pos
			dir.y = 0.0
			if dir.length() > 0.01 and not leg.get("crab", false):
				car.look_at(pos - dir if leg.get("reverse", false) else pos + dir, Vector3.UP)
			car.global_position = pos.move_toward(target, leg.speed * dt)
			await physics_frame
	for i in 60:
		if not session.is_running():
			break
		await physics_frame
	if session.is_running():
		session.abort()
	var result := session.result
	if on_end.is_valid():
		on_end.call(runner)
	runner.queue_free()
	await process_frame
	return result


## A runner on the stop junction that is not driven by the tests; for the probe and session.
func spawn_runner(scenario: PackedScene = null) -> ExamRunner:
	var runner: ExamRunner = RUNNER.instantiate()
	runner.print_results = false
	runner.scenario_scene = scenario if scenario else STOP_JUNCTION
	root.add_child(runner)
	return runner


func _with(what: String, r: ScenarioResult) -> String:
	return "%s: %s" % [what, r.summary() if r else "no result"]
