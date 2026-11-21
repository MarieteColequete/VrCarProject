extends TestCase
## Pedestrians as drawn: a survivor of the retro characters kit, the body's height, facing -Z,
## standing idle when still and walking when moving, each pedestrian of the world drawn once and
## gone when it leaves.


func run() -> void:
	_test_model()
	await _test_view()


func _test_model() -> void:
	var man := PedestrianModel.make(0, 1.8)
	var woman := PedestrianModel.make(1, 1.6)
	expect(man != null and woman != null, "a survivor is made from the kit's model")
	if man == null or woman == null:
		return
	root.add_child(man)
	root.add_child(woman)
	var skins := [man, woman].map(func(p: PedestrianModel) -> String:
		var mesh := p.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
		return ((mesh.material_override as StandardMaterial3D).albedo_texture as Texture2D) \
			.resource_path.get_file())
	expect(skins == ["humanMaleA.png", "humanFemaleA.png"],
		"the variants are the two survivors: %s" % [skins])
	var skeleton := man.find_child("Skeleton3D", true, false) as Skeleton3D
	var head := skeleton.global_transform * skeleton.get_bone_global_rest(
		skeleton.find_bone("Head_end"))
	var toes := skeleton.global_transform * skeleton.get_bone_global_rest(
		skeleton.find_bone("LeftToes_end"))
	expect(absf(head.origin.y - 1.8) < 0.1, "the survivor stands as tall as its body: %.2f m"
		% head.origin.y)
	expect(toes.origin.z < -0.05, "and faces -Z, as road users do")

	var library := PedestrianModel.library()
	expect(library.get_animation(&"idle").loop_mode == Animation.LOOP_LINEAR
		and library.get_animation(&"run").loop_mode == Animation.LOOP_LINEAR
		and library.get_animation(&"run").get_track_count() > 0,
		"the idle and run animations come from the kit, looping")
	expect(man.playing() == PedestrianModel.IDLE, "a new pedestrian stands idle")
	man.set_speed(1.4)
	var player := man.find_child("AnimationPlayer", true, false) as AnimationPlayer
	expect(man.playing() == PedestrianModel.RUN and player.speed_scale < 1.0
		and player.speed_scale >= PedestrianModel.SLOWEST,
		"walking plays the run, slowed to the walk: %.2f" % player.speed_scale)
	man.set_speed(0.0)
	expect(man.playing() == PedestrianModel.IDLE, "and stopping, idle again")
	man.free()
	woman.free()


func _test_view() -> void:
	var holder := Node3D.new()
	root.add_child(holder)
	var world := World.new()
	Simulation.empty_world(world)
	var view := TrafficView.new(holder, 4)
	var id := world.spawn({agent = {pedestrian = true, body_size = Vector3(0.5, 1.8, 0.5),
		position = Vector3(2, 0, -3), facing = Vector3.RIGHT, current_speed = 1.4}})
	world.spawn({agent = {position = Vector3(0, 0, -20)}})
	view.draw(world)
	var walker := view.walker(id)
	expect(walker != null and view.counts().get(TrafficView.WALKER) == 1
		and view.counts().size() == 2, "a pedestrian is drawn as a survivor, a car as a car: %s"
		% [view.counts()])
	if walker:
		expect(walker.position.is_equal_approx(Vector3(2, 0, -3))
			and (-walker.basis.z).is_equal_approx(Vector3.RIGHT),
			"it stands where the world has it, facing its way")
		expect(walker.playing() == PedestrianModel.RUN, "and walks while moving")
	world.despawn(id)
	view.draw(world)
	expect(view.walker(id) == null and not view.counts().has(TrafficView.WALKER),
		"a pedestrian leaving the world leaves the view")
	view.clear()
	holder.queue_free()
	await process_frame
