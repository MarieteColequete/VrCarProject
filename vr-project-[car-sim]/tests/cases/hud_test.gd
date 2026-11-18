extends TestCase
## The debug HUD and sandbox: the exam bindings, the briefing, beginning, the fault feed, road user
## reactions, the performance readout, the result, moving to the next scenario, and the result as
## plain data for a UI.

const SANDBOX := preload("res://scenarios/debug/scenario_sandbox.tscn")
const EXAM_ACTIONS: Array[StringName] = [
	&"exam_begin", &"exam_restart", &"exam_next_scenario", &"toggle_debug_hud"]


func run() -> void:
	_test_bindings()
	await _test_sandbox()


func _has_event(action: StringName, type: String) -> bool:
	for event in InputMap.action_get_events(action):
		if event.is_class(type):
			return true
	return false


func _test_bindings() -> void:
	for action in EXAM_ACTIONS:
		expect(InputMap.has_action(action) and _has_event(action, "InputEventKey")
			and _has_event(action, "InputEventJoypadButton"),
			"%s is bound on the keyboard and the gamepad" % action)


func _press(hud: DebugHud, action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	hud._unhandled_input(event)


func _test_sandbox() -> void:
	var sandbox := SANDBOX.instantiate()
	root.add_child(sandbox)
	var runner: ExamRunner = sandbox.get_node("Runner")
	var hud: DebugHud = sandbox.get_node("DebugHud")
	runner.print_results = false
	await process_frame
	var session := runner.session
	expect(session.state == ExamSession.State.BRIEFING and hud.message_panel.visible
		and hud.message_label.text.contains(session.definition.briefing)
		and hud.message_label.text.contains("Enter or Start to begin"),
		"the sandbox waits on the briefing, with the begin keys read from the input map")

	_press(hud, &"exam_begin")
	expect(session.is_running() and not hud.message_panel.visible, "exam_begin starts the attempt")
	var drift: FaultDef = load(FAULTS % "lane_drift")
	session.report_fault(drift, Vector3.ZERO)
	expect(hud.feed.get_child_count() == 1
		and (hud.feed.get_child(0) as Label).text.contains(drift.title),
		"a committed fault appears in the feed")
	await physics_frame
	await physics_frame
	expect(hud.time_label.text.contains("/ 90"), "the time shows against the limit")

	var lane := Path3D.new()
	lane.curve = Curve3D.new()
	lane.curve.add_point(at(70.0))
	lane.curve.add_point(at(-40.0))
	runner.scenario.add_child(lane)
	var follower := ScriptedAgent.new()
	follower.name = "Follower"
	follower.path = lane
	follower.speed = 8.0
	runner.add_road_user(follower)
	await frames(600)
	var reaction_shown := false
	for line: Label in hud.feed.get_children():
		if line.text.contains("Follower stopped"):
			reaction_shown = true
	expect(reaction_shown, "the feed shows how other road users react")
	expect(hud.performance_label.text.contains("traffic")
		and hud.performance_label.text.contains("road users"),
		"the readout shows the traffic pipeline's share of the frame: %s" % hud.performance_label.text)

	session.abort()
	expect(hud.message_panel.visible and hud.message_label.text.contains("FAILED")
		and hud.message_label.text.contains("Minor"), "the result shows the outcome and the tiers")

	var data := session.result.to_dict()
	expect(data.scenario.id == "stop_junction" and data.tiers.size() == 3
		and not String(data.faults[0].description).is_empty(),
		"the result data names the scenario, counts each tier, and describes each fault")

	_press(hud, &"exam_next_scenario")
	await process_frame
	await process_frame
	expect(runner.scenario.definition.id == &"traffic_lights" and hud.feed.get_child_count() == 0
		and session.state == ExamSession.State.BRIEFING,
		"exam_next_scenario loads the next catalogued scenario afresh")

	_press(hud, &"toggle_debug_hud")
	expect(not hud.visible, "toggle_debug_hud hides the overlay")
	sandbox.queue_free()
	await process_frame
