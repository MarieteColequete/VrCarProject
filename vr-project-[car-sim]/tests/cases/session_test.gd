extends TestCase
## The exam session: steps, check windows, dedupe, and the result as plain data.

const STEPS_FIXTURE := preload("res://tests/fixtures/steps_fixture.tscn")


func run() -> void:
	await _test_session()


func _test_session() -> void:
	var step_titles: Array[String] = []
	var record_steps := func(runner: ExamRunner) -> void:
		runner.session.step_changed.connect(func(step: ScenarioStep) -> void:
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
	var a := Node.new()
	var b := Node.new()
	runner.session.report_fault(lane, Vector3.ZERO, a)
	runner.session.report_fault(lane, Vector3.ZERO, a)
	runner.session.report_fault(lane, Vector3.ZERO, b)
	expect(runner.session.faults.size() == 2,
		"a repeat from the same check within the window is dropped, another check's is kept")
	a.free()
	b.free()
	runner.queue_free()
	await process_frame
