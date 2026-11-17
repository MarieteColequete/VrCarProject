extends TestCase
## The framework's building blocks: episodes, zone watching, default faults, configuration
## warnings, and the per-tick caches.

const CHECKS := "res://scenarios/checks/"
const POLICY := preload("res://scenarios/data/default_policy.tres")


class Watcher extends Check:
	var seen := 0

	func count(_p: VehicleProbe) -> void:
		seen += 1


func run() -> void:
	_test_episode()
	_test_default_faults()
	_test_configuration_warnings()
	await _test_watch()
	await _test_caches()


func _test_episode() -> void:
	var episode := Episode.new()
	expect(not episode.update(true, 0.5, 1.0) and not episode.update(true, 0.5, 1.0),
		"an episode does not fire before it outlasts its grace")
	expect(episode.update(true, 0.5, 1.0), "it fires once it lasts longer than the grace")
	expect(not episode.update(true, 0.5, 1.0), "and only once while it lasts")
	episode.update(false, 0.5, 1.0)
	expect(episode.time == 0.0 and not episode.reported, "it resets when the condition ends")


func _test_default_faults() -> void:
	var missing := PackedStringArray()
	var found := 0
	for file in DirAccess.get_files_at(CHECKS):
		if not file.ends_with(".gd"):
			continue
		var script: GDScript = load(CHECKS + file)
		var node: Object = script.new()
		if node is Check:
			for property in node.get_property_list():
				if property.class_name == &"FaultDef":
					found += 1
					var fault: FaultDef = node.get(property.name)
					if fault == null or POLICY.get_tier(fault.tier) == null:
						missing.append("%s.%s" % [file.get_basename(), property.name])
		node.free()
	expect(found > 0 and missing.is_empty(),
		"all %d fault exports default to a fault of a policy tier %s" % [found, missing])


func _test_configuration_warnings() -> void:
	var stop := StopCheck.new()
	expect(stop._get_configuration_warnings().size() == 2,
		"a stop check without its zones warns about both")
	var approach := TriggerZone.new()
	var line := TriggerZone.new()
	stop.approach_zone = approach
	stop.line_zone = line
	expect(stop._get_configuration_warnings().is_empty(), "a configured stop check has no warning")
	var junction := JunctionCheck.new()
	junction.judge_on_exit = true
	expect(junction._get_configuration_warnings().size() == 1,
		"a junction check without exits asks for them")
	expect(approach._get_configuration_warnings().size() == 1, "a zone without a box shape warns")
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	approach.add_child(shape)
	expect(approach._get_configuration_warnings().is_empty(), "a zone with a box shape has no warning")
	var agent := ScriptedAgent.new()
	expect(agent._get_configuration_warnings().size() == 1, "an agent without a path warns")
	for node: Node in [stop, approach, line, junction, agent]:
		node.free()


func _test_watch() -> void:
	var runner := spawn_runner()
	await process_frame
	var watcher := Watcher.new()
	watcher.session = runner.session
	var zone := TriggerZone.new()
	watcher.watch(zone, watcher.count)
	watcher.watch(null, watcher.count)
	var stranger := VehicleProbe.new()
	zone.vehicle_entered.emit(stranger)
	expect(watcher.seen == 0, "watch ignores another car's probe")
	zone.vehicle_entered.emit(runner.session.probe)
	expect(watcher.seen == 1, "watch passes on the session's car while live")
	runner.session.abort()
	zone.vehicle_entered.emit(runner.session.probe)
	expect(watcher.seen == 1, "watch passes nothing once the attempt has ended")
	for node: Node in [watcher, zone, stranger]:
		node.free()
	runner.queue_free()
	await process_frame


func _test_caches() -> void:
	var runner := spawn_runner()
	await process_frame
	await physics_frame
	var probe := runner.session.probe
	var first := probe.wheels()
	expect(first == probe.wheels(), "the probe's wheels are stable within a tick")
	runner.car.global_position += Vector3(0, 0, -1)
	expect(probe.wheels()[0].is_equal_approx(first[0] + Vector3(0, 0, -1)),
		"they follow the car as soon as it moves")
	expect(is_same(runner.session.wheel_crossings(), runner.session.wheel_crossings()),
		"the wheel crossings are computed once per tick and shared")
	runner.queue_free()
	await process_frame
