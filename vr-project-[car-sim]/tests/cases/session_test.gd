extends TestCase
## The exam session: steps, check windows, dedupe, and the result as plain data.

const STEPS_FIXTURE := preload("res://tests/fixtures/steps_fixture.tscn")


func run() -> void:
	await _test_session()
	await _test_same_drive_same_events()


func _test_session() -> void:
	var step_titles: Array[String] = []
	var record_steps := func(exam: ExamRunner) -> void:
		exam.session.step_changed.connect(func(step: ScenarioStep) -> void:
			step_titles.append(step.title))

	var r := await drive([{to = Vector3(0, 0, -45), speed = 8.0}], STEPS_FIXTURE, record_steps)
	expect(r.reason == &"completed" and r.steps_completed == 2 and r.step_count == 2,
		"both steps complete in order: " + r.summary())
	expect(step_titles.size() == 2 and step_titles[0] == "Reach the first marker",
		"step_changed reports each step as it starts: %s" % [step_titles])
	expect_only(r, &"speeding_serious", "a check limited to step two faults only in step two", &"")

	r = await drive([
		{to = Vector3(0, 0, -20), speed = 8.0}, {to = Vector3(0, 0, -45), speed = 2.0}],
		STEPS_FIXTURE)
	expect_clean(r, "speeding only before its step is not a fault")

	var dict := r.to_dict()
	expect(dict.reason == "completed" and dict.passed and dict.steps_completed == 2
		and dict.faults is Array, "to_dict carries the outcome as plain data")

	var runner := spawn_runner()
	await process_frame
	expect(runner.session.is_running(), "an autostarting runner's session is running after one frame")
	var lane: FaultDef = load(FAULTS % "lane_drift")
	var sess := {state = ExamSession.State.RUNNING, elapsed = 0.0, last_report = {}, faults = [],
		definition = runner.session.definition}
	var d := Delta.new()
	for source in [1, 1, 2]:
		ExamLogic._report(sess, source, lane, Vector3.ZERO, null, d)
	expect(sess.faults.size() == 2 and d.events.size() == 2,
		"a repeat from the same rule within the window is dropped, another rule's is kept")
	runner.queue_free()
	await process_frame


## Every event of a drive that crosses lines, speeds, and runs the stop line, as text.
func _event_log() -> Array:
	var lines := []
	var on_spawn := func(runner: ExamRunner) -> void:
		runner.world_runner.events_emitted.connect(func(events: Array[WorldEvent]) -> void:
			for event in events:
				lines.append("%s %d %.3f" % [event.kind, event.entity, event.time]))
	await drive([{to = at(20.0), speed = 15.0}, {to = Vector3(-1.75, 0, 0), speed = 15.0},
		{to = Vector3(-1.75, 0, -40), speed = 15.0}], null, on_spawn)
	return lines


func _test_same_drive_same_events() -> void:
	var first := await _event_log()
	var second := await _event_log()
	expect(first.size() > 5 and first == second,
		"the same drive gives the same events, scoring included, every time (%d events)"
		% first.size())
