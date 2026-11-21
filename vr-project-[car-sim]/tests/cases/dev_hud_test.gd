extends TestCase
## The developer's overlay: switched on from the Map Kit's play file, its bindings, its readouts
## after a drive, the time scale, pausing and stepping a single tick, and moving the car to
## another spawn of the map.

const SANDBOX := preload("res://scenarios/debug/map_sandbox.tscn")
const TINY := "res://tests/fixtures/maps/tiny/tiny.tscn"
const DEV_KEYS := {&"dev_toggle_hud": KEY_F3, &"dev_free_camera": KEY_F4, &"dev_slower": KEY_F5,
	&"dev_faster": KEY_F6, &"dev_pause": KEY_F7, &"dev_step": KEY_F8, &"dev_next_spawn": KEY_F9}


func run() -> void:
	_test_bindings()
	var saved: Variant = _save_play_file()
	await _test_sandbox()
	_restore_play_file(saved)


func _test_bindings() -> void:
	var bound := true
	for action: StringName in DEV_KEYS:
		var keys: Array = InputMap.action_get_events(action) if InputMap.has_action(action) else []
		bound = bound and keys.size() == 1 \
			and (keys[0] as InputEventKey).physical_keycode == DEV_KEYS[action]
	expect(bound, "the dev actions are bound to F3 to F9")


## The play file's bytes, or null when there is none.
func _save_play_file() -> Variant:
	if not FileAccess.file_exists(MapSandbox.PLAY_FILE):
		return null
	return FileAccess.get_file_as_bytes(MapSandbox.PLAY_FILE)


func _restore_play_file(saved: Variant) -> void:
	if saved == null:
		DirAccess.remove_absolute(MapSandbox.PLAY_FILE)
		return
	var file := FileAccess.open(MapSandbox.PLAY_FILE, FileAccess.WRITE)
	file.store_buffer(saved)


## The tiny map with a second spawn 30 m ahead of its first.
func _two_spawn_map() -> PackedScene:
	var road_map := (load(TINY) as PackedScene).instantiate() as RoadMap
	var second := MapSpawn.new()
	second.name = "SecondSpawn"
	second.position = Vector3(8.0, 0.0, -30.0)
	road_map.add_child(second)
	second.owner = road_map
	var scene := PackedScene.new()
	scene.pack(road_map)
	road_map.free()
	return scene


func _test_sandbox() -> void:
	var config := ConfigFile.new()
	config.set_value("play", "map", TINY)
	config.set_value("play", "dev_hud", false)
	config.save(MapSandbox.PLAY_FILE)
	expect(not MapSandbox.dev_hud_wanted(), "dev_hud false in the play file asks for no DevHud")
	config.set_value("play", "dev_hud", true)
	config.save(MapSandbox.PLAY_FILE)
	expect(MapSandbox.dev_hud_wanted(), "dev_hud true in the play file asks for the DevHud")

	var sandbox: MapSandbox = SANDBOX.instantiate()
	root.add_child(sandbox)
	var runner := sandbox.runner
	runner.print_results = false
	var hud := sandbox.dev
	var debug_hud: DebugHud = sandbox.get_node("DebugHud")
	expect(hud != null and hud.get_parent() == sandbox and runner.map_scene != null
		and runner.map_scene.resource_path == TINY,
		"the map sandbox drives the chosen map with a DevHud beside the DebugHud")
	expect(debug_hud.keys_label.text.contains(DevHud.key_hint_text())
		and debug_hud.keys_label.text.contains("F9"), "the DebugHud's hints list the dev keys")

	await frames(120)
	await process_frame
	expect(hud.fps_label.text.begins_with("FPS") and hud.speed_label.text.ends_with("km/h")
		and hud.position_label.text.contains("heading") and hud._frame_ms.size() > 60,
		"after 120 ticks the readouts are filled in: %s, %s" % [hud.fps_label.text,
			hud.speed_label.text])
	expect(hud.session_label.text.begins_with("session briefing")
		and hud.session_label.text.contains("faults none"),
		"the session readout shows the state and the faults: %s" % hud.session_label.text)

	hud.slower()
	expect(is_equal_approx(Engine.time_scale, 0.5), "slower halves the time scale")
	hud.slower()
	hud.slower()
	expect(is_equal_approx(Engine.time_scale, 0.25), "the time scale stops at a quarter")
	for i in 5:
		hud.faster()
	expect(is_equal_approx(Engine.time_scale, 2.0), "the time scale stops at double")
	hud.set_time_scale(DevHud.TIME_SCALES.find(1.0))
	expect(is_equal_approx(Engine.time_scale, 1.0), "the time scale goes back to real time")

	hud.toggle_pause()
	var paused_at := runner.world().tick
	await frames(5)
	expect(tree.paused and runner.world().tick == paused_at, "pausing stops the world")
	hud.step_once()
	await frames(5)
	expect(tree.paused and runner.world().tick == paused_at + 1,
		"a step while paused runs exactly one tick (%d to %d)" % [paused_at, runner.world().tick])
	hud.toggle_pause()
	await frames(2)
	expect(not tree.paused and runner.world().tick > paused_at + 1, "unpausing lets it go on")

	runner.load_map(_two_spawn_map())
	await process_frame
	expect(hud.spawn_count(runner.map_scene) == 2, "the map has two spawns")
	hud.teleport(1)
	await process_frame
	var spawn := runner.scenario.map.spawns()[1]
	expect(runner.map_spawn == 1
		and runner.car.global_position.is_equal_approx(spawn.global_position),
		"teleporting to spawn 1 puts the car there")
	hud.teleport(2)
	await process_frame
	expect(runner.map_spawn == 0, "teleporting past the last spawn wraps round to the first")

	hud.set_overlay(true)
	expect(hud._overlay != null and hud._overlay.visible, "the zones and lanes overlay builds")

	hud.toggle_free_camera()
	expect(tree.paused and hud.free_camera.current, "the free camera takes the view and pauses")
	hud.toggle_free_camera()
	expect(not tree.paused and not hud.free_camera.current,
		"closing the free camera gives the view back and lets the drive go on")

	hud.slower()
	sandbox.queue_free()
	await process_frame
	expect(is_equal_approx(Engine.time_scale, 1.0) and not tree.paused,
		"freeing the DevHud leaves the engine at real time and unpaused")
