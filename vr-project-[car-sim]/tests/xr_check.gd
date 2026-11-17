extends SceneTree
## The game through a real OpenXR runtime: the busy junction with 200 extra road users, rendered in
## the headset (or an emulated one, such as Monado's simulated headset) for a span of frames. Run
## from the repository root, without --headless, with an OpenXR runtime active:
##   godot --path 'vr-project-[car-sim]' -s res://tests/xr_check.gd
## It checks that OpenXR starts, the session gains focus, and the driver's view uses the headset,
## then reports the frame times and the frames that ran late: longer than 1.5 times the headset's
## frame budget, which a headset shows as a repeated or reprojected frame. It prints
## "XR CHECK PASS" or "XR CHECK FAIL"; read that line rather than the exit code, since the
## separate render thread still aborts at exit under OpenXR (Godot issue 119000).
## XR_WARM_S and XR_SPAN_S set the warm-up and measured seconds (15 and 30); XR_SCALE multiplies
## the eye resolution the runtime recommends.

const SCENARIO := "res://scenarios/scenes/busy_junction/busy_junction.tscn"
const RUNNER := "res://scenarios/scenes/exam_runner.tscn"
const EXTRA_LANES := 10
const PER_LANE := 20

var _focused := false


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var xr := XRServer.find_interface("OpenXR") as OpenXRInterface
	if xr == null or not xr.is_initialized():
		_finish(false, "OpenXR did not start; is a runtime active?")
		return
	_focused = xr.get_session_state() == 5  # XR_SESSION_STATE_FOCUSED
	xr.session_focussed.connect(func() -> void: _focused = true)
	var scale := float(OS.get_environment("XR_SCALE")) if OS.has_environment("XR_SCALE") else 1.0
	if scale != 1.0:
		xr.render_target_size_multiplier = scale
	var runner: ExamRunner = load(RUNNER).instantiate()
	runner.scenario_scene = load(SCENARIO)
	runner.print_results = false
	root.add_child(runner)
	runner.car.input_enabled = false
	await process_frame
	var system := _add_traffic()
	var view := root.find_children("*", "DriverView", true, false).front() as DriverView
	var warm := _seconds("XR_WARM_S", 15)
	var span := _seconds("XR_SPAN_S", 30)
	var until := Time.get_ticks_msec() + warm * 1000
	while Time.get_ticks_msec() < until:
		await process_frame
	var frames := PackedFloat64Array()
	var last := Time.get_ticks_usec()
	until = Time.get_ticks_msec() + span * 1000
	while Time.get_ticks_msec() < until:
		await process_frame
		var now := Time.get_ticks_usec()
		frames.append((now - last) / 1000.0)
		last = now
	var budget := 1000.0 / xr.display_refresh_rate if xr.display_refresh_rate > 0.0 else 1000.0 / 90.0
	var late := 0
	var total := 0.0
	for f in frames:
		total += f
		if f > budget * 1.5:
			late += 1
	var sorted := frames.duplicate()
	sorted.sort()
	print("XR %.0f Hz, eyes %s, %d road users: %d frames, mean %.2f ms, p99 %.2f ms, late %d (%.2f%%)"
		% [xr.display_refresh_rate, xr.get_render_target_size(), system.count(), frames.size(),
		total / frames.size(), sorted[int(sorted.size() * 0.99)], late,
		100.0 * late / frames.size()])
	if not _focused:
		_finish(false, "the session never gained focus")
	elif view == null or not view.vr:
		_finish(false, "the driver's view did not switch to the headset")
	else:
		_finish(true, "")


## Ten looping lanes of 20 road users each, with a light per lane, beside the junction.
func _add_traffic() -> TrafficSystem:
	var system: TrafficSystem
	for l in EXTRA_LANES:
		var light := TrafficLight.new()
		light.red_time = 6.0 + l * 0.3
		light.green_time = 8.0
		root.add_child(light)
		var lane := TrafficLane.new()
		lane.curve = Curve3D.new()
		lane.curve.add_point(Vector3(40 + l * 4.0, 0, 120))
		lane.curve.add_point(Vector3(40 + l * 4.0, 0, -120))
		lane.light = light
		lane.stop_offset = 120.0
		root.add_child(lane)
		for i in PER_LANE:
			var agent := ScriptedAgent.new()
			agent.path = lane
			agent.speed = 10.0 + (i % 3)
			agent.loop = true
			agent.start_delay = i * 1.2
			root.add_child(agent)
			system = TrafficSystem.of(agent)
	return system


func _seconds(variable: String, fallback: int) -> int:
	return int(OS.get_environment(variable)) if OS.has_environment(variable) else fallback


func _finish(ok: bool, reason: String) -> void:
	print("XR CHECK PASS" if ok else "XR CHECK FAIL: " + reason)
	quit(0 if ok else 1)
