extends TestCase
## The car's mirrors ([CarMirror]): the reflected camera's geometry, the glass on the Kiri '86 set
## up for the driver, the setting that turns them off, and the gaze rule judging looks at them
## ([GazeRule]): a look held in a mirror's cone, too short a look, the interior mirror, and the
## eyes off the road.

const CAR := preload("res://scenarios/scenes/debug_car.tscn")


func run() -> void:
	_test_geometry()
	await _test_on_car()
	await _test_off()
	_test_rule()


func _test_geometry() -> void:
	var reflected := CarMirror.reflect(Vector3(0.3, 0.2, 1.0), Vector3.ZERO, Vector3.BACK)
	expect(reflected.is_equal_approx(Vector3(0.3, 0.2, -1.0)), "reflecting across the glass")
	var glass := Transform3D(Basis.IDENTITY, Vector3.ZERO)
	var v := CarMirror.view(Vector3(0.1, 0.2, 1.0), glass, Vector2(0.2, 0.1))
	expect(not v.is_empty() and (v.transform as Transform3D).origin.is_equal_approx(
		Vector3(0.1, 0.2, -1.0)), "the camera stands at the reflected eye")
	expect(is_equal_approx(v.near, 1.0), "its near plane is the glass, 1 m away")
	expect((v.offset as Vector2).is_equal_approx(Vector2(0.1, -0.2)),
		"its view is offset to the glass's centre: %s" % v.offset)
	var looks: Vector3 = -(v.transform as Transform3D).basis.z
	expect(looks.is_equal_approx(Vector3.BACK), "and it looks out through the glass")
	expect(CarMirror.view(Vector3(0.0, 0.0, -1.0), glass, Vector2.ONE).is_empty(),
		"an eye behind the glass sees nothing in it")
	var normal := CarMirror.aim(Vector3.ZERO, Vector3(1, 0, 0), Vector3(0, 0, 1))
	expect(normal.is_equal_approx(Vector3(1, 0, 1).normalized()),
		"a mirror is set halfway between the eye and what it shows")


func _test_on_car() -> void:
	var car: Node3D = CAR.instantiate()
	root.add_child(car)
	await physics_frame
	var mirrors: Array = car.mirrors
	var probe: VehicleProbe = car.probe
	expect(mirrors.size() == 3 and probe.mirrors.size() == 3,
		"the car has an interior mirror and two door mirrors")
	if mirrors.size() != 3:
		car.queue_free()
		await process_frame
		return
	var eye: Vector3 = car.driver_view.eye().global_position
	for mirror: CarMirror in mirrors:
		var facing := mirror.global_basis.z.dot((eye - mirror.global_position).normalized())
		expect(facing > 0.5, "%s faces the driver: %.2f" % [mirror.name, facing])
		mirror.render()
		var back := -mirror.camera.global_basis.z
		expect(back.dot(car.global_basis.z) > 0.5,
			"%s shows what is behind the car: %s" % [mirror.name, back])
	expect(probe.mirrors[1].x < 0.0 and probe.mirrors[2].x > 0.0 and absf(probe.mirrors[0].x) < 0.1,
		"the left mirror is on the left, the right on the right, the interior one in the middle")
	var model: PlayerCarModel = car.model
	for key: StringName in [&"rear", &"left", &"right"]:
		var glass := model.mirror_glass.get(key) as MeshInstance3D
		var mirror: CarMirror = mirrors[[&"rear", &"left", &"right"].find(key)]
		expect(glass != null and mirror.glass == glass and glass.get_parent() == model.body
			and glass.layers == Layers.MIRROR_VISUAL
			and (glass.material_override as StandardMaterial3D).albedo_texture
			== mirror.viewport.get_texture(),
			"the %s mirror's picture is on the model's own glass" % key)
		var arrays := glass.mesh.surface_get_arrays(0) if glass else []
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV] if glass else PackedVector2Array()
		var spans := uvs.size() > 0
		for uv in uvs:
			spans = spans and uv.x >= -0.001 and uv.x <= 1.001 and uv.y >= -0.001 and uv.y <= 1.001
		expect(spans, "its UVs span the glass")
	var viewport: SubViewport = mirrors[0].viewport
	expect(viewport.size.x == 512 and viewport.size.y < 200, "the interior mirror's picture is %s"
		% viewport.size)
	car.queue_free()
	await process_frame


func _test_off() -> void:
	var before: Variant = ProjectSettings.get_setting(CAR.instantiate().MIRRORS_SETTING, null)
	ProjectSettings.set_setting("car/mirrors", "off")
	var car: Node3D = CAR.instantiate()
	root.add_child(car)
	await physics_frame
	expect(car.mirrors.is_empty() and car.probe.mirrors.size() == 3,
		"with the mirrors off, none are drawn, and the checks still know where they are")
	ProjectSettings.set_setting("car/mirrors", before)
	car.queue_free()
	await process_frame


## A car at the origin facing -Z with mirrors like the Kiri '86's, the eye in the driver's seat
## looking at [param target] (car space).
func _car(target: Vector3, moving := true) -> CarState:
	var car := CarState.new()
	car.mirrors = PackedVector3Array([Vector3(0, 1.3, -0.07), Vector3(-0.875, 0.975, -0.465),
		Vector3(0.875, 0.975, -0.465)])
	car.eye = Vector3(-0.35, 1.23, 0.2)
	car.look = (target - car.eye).normalized()
	car.stopped = not moving
	car.direction = VehicleProbe.Direction.FORWARD if moving else VehicleProbe.Direction.STOPPED
	return car


func _params() -> Dictionary:
	var gaze := GazeCheck.new()
	var p := gaze.rule_params(null)
	gaze.free()
	return p


## Runs the gaze rule for [param seconds] with the look at [param target]; the state after.
func _look(p: Dictionary, s: Dictionary, target: Vector3, seconds: float,
		faults: Array = []) -> Dictionary:
	var f := RuleFrame.new()
	f.dt = 1.0 / 60.0
	var start: float = s.get("clock", 0.0)
	var t := 0.0
	while t < seconds - 0.00001:
		t += f.dt
		f.elapsed = start + t
		f.car = _car(target)
		var r := GazeRule.step(p, s, f, true)
		s = r.state
		faults.append_array(r.faults.map(func(x: Array) -> StringName: return (x[0] as FaultDef).id))
	s.clock = start + t
	return s


func _test_rule() -> void:
	var p := _params()
	var left: Vector3 = _car(Vector3.ZERO).mirrors[1]
	var s := _look(p, GazeRule.initial(p), left, 0.1)
	var f := RuleFrame.new()
	f.elapsed = s.clock
	expect(not GazeRule.looked(p, s, f, &"mirror_left"), "a tenth of a second is not a look")
	s = _look(p, s, left, 0.2)
	f.elapsed = s.clock
	expect(GazeRule.looked(p, s, f, &"mirror_left"), "held in the mirror's cone, it is a look")
	var interior: Vector3 = _car(Vector3.ZERO).mirrors[0]
	s = _look(p, GazeRule.initial(p), interior, 0.3)
	f.elapsed = s.clock
	expect(GazeRule.looked(p, s, f, &"interior") and not GazeRule.looked(p, s, f, &"mirror_right")
		and not GazeRule.looked(p, s, f, &"mirror_left"),
		"a look in the interior mirror is that look, not a door mirror's")
	var no_mirrors := CarState.new()
	no_mirrors.look = Vector3(-1, 0, -1).normalized()
	expect(is_inf(no_mirrors.look_off_mirror(1)), "a car without mirrors has no mirror to look at")

	var q := p.duplicate()
	q.eyes_off_road_after = 2.0
	var faults := []
	var away := Vector3(-3.0, 1.0, 1.0)
	var t := _look(q, GazeRule.initial(q), away, 1.5, faults)
	expect(faults.is_empty(), "a look away for 1.5 s is not judged")
	t = _look(q, t, away, 1.0, faults)
	expect(faults == [&"eyes_off_road"], "past 2 s it is one fault: %s" % [faults])
	t = _look(q, t, away, 2.0, faults)
	expect(faults.size() == 1, "and stays one while the eyes stay away")
	t = _look(q, t, Vector3(-0.35, 1.2, -10.0), 0.1, faults)
	t = _look(q, t, away, 2.5, faults)
	expect(faults.size() == 2, "looking back at the road and away again is another")
	faults.clear()
	_look(q, GazeRule.initial(q), left, 5.0, faults)
	expect(faults.is_empty(), "a long look in a mirror is not off the road")
