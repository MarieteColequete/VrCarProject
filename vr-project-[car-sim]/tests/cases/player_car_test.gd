extends TestCase
## The player's car as drawn: the Kiri '86 fitted to the car, the driver seated behind its
## steering wheel, its live parts (wheels, steering wheel, lights), and the instruments, all
## following the car's state; and its cabin, cut into parts each in a textured material of its own.

const CAR := preload("res://scenarios/scenes/debug_car.tscn")
const CAR_SCRIPT := preload("res://scenarios/scenes/debug_car.gd")


func run() -> void:
	_test_fit()
	_test_box_uvs()
	_test_cabin()
	await _test_live()
	_test_instruments()


func _test_fit() -> void:
	var model := PlayerCarModel.make(2.6)
	expect(model != null and model.wheels.size() == 4 and model.steering_wheel != null,
		"the car has four wheels and a steering wheel of its own")
	if model == null:
		return
	root.add_child(model)
	var fronts := model.wheels.filter(func(w: Dictionary) -> bool: return w.front)
	var at := model.wheels.map(func(w: Dictionary) -> Vector3:
		return (w.node as Node3D).global_position)
	var front_z: float = fronts.map(func(w: Dictionary) -> float:
		return (w.node as Node3D).global_position.z).reduce(func(a, b): return a + b) / 2.0
	var lowest: float = at.map(func(p: Vector3) -> float: return p.y).min()
	expect(absf(front_z + 1.3) < 0.02, "its front wheels are 1.3 m ahead, -Z: %.2f" % front_z)
	expect(absf(lowest - model.radius) < 0.03 and model.radius > 0.25 and model.radius < 0.35,
		"its wheels stand on the ground: radius %.2f m" % model.radius)
	expect(model.steering_centre.x < -0.2 and model.steering_centre.z < 0.0,
		"the steering wheel is on the left, ahead of the car's middle: %s" % model.steering_centre)
	var column := (model.steering_wheel.global_transform.basis * model.steering_axis).normalized()
	expect(column.z > 0.5, "the steering column points back at the driver: %s" % column)
	var glass := 0
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var m := mesh.get_surface_override_material(0) as StandardMaterial3D
		if m and m.resource_name == "UCB_Lights_and_Glass_Transperent":
			glass += 1
			expect(m.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA and m.albedo_color.a < 0.5,
				"%s is see-through" % mesh.name)
	expect(glass >= 5, "the windows and lamp covers are glass: %d" % glass)
	var paint: StandardMaterial3D = null
	var plates: StandardMaterial3D = null
	for mesh: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for surface in mesh.mesh.get_surface_count():
			var m := mesh.get_surface_override_material(surface) as StandardMaterial3D
			if m and m.resource_name == "kiri86_Bodymat":
				paint = m
			elif m and m.resource_name == "Numberplates_Misk_U":
				plates = m
	expect(paint != null and paint.clearcoat_enabled, "the paint has a clear coat")
	expect(plates != null and plates.normal_enabled and plates.normal_texture != null,
		"the number plates' letters stand out, from their height map")
	model.free()


func _test_box_uvs() -> void:
	# A 1 m square facing up, and a wall facing +X, as two triangles each, wound as Godot's are.
	var floor := PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 0, 1),
		Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1)])
	var uvs := PlayerCarModel.box_uvs(floor, Transform3D.IDENTITY, Basis.IDENTITY, 0.5)
	var span := Vector2.ZERO
	for uv in uvs:
		span = span.max(uv)
	expect(span.is_equal_approx(Vector2(2.0, 2.0)), "a metre of floor is two repeats at half a metre each: %s" % span)
	var wall := PackedVector3Array([Vector3(0, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)])
	var on_wall := PlayerCarModel.box_uvs(wall, Transform3D.IDENTITY, Basis.IDENTITY, 1.0)
	expect(on_wall[1].is_equal_approx(Vector2(0, 1)) and on_wall[2].is_equal_approx(Vector2(1, 0)),
		"a wall facing sideways is laid out along its length and height: %s" % on_wall)
	expect(PlayerCarModel.cabin_zone(Vector3(0.0, 1.3, 0.5), Vector3.DOWN) == &"headliner"
		and PlayerCarModel.cabin_zone(Vector3(-0.3, 0.38, -0.5), Vector3.UP) == &"floor"
		and PlayerCarModel.cabin_zone(Vector3(-0.35, 0.6, 0.3), Vector3.UP) == &"seats"
		and PlayerCarModel.cabin_zone(Vector3(-0.55, 0.7, 0.3), Vector3.LEFT) == &"bolsters"
		and PlayerCarModel.cabin_zone(Vector3(-0.68, 0.8, 0.2), Vector3.RIGHT) == &"doors"
		and PlayerCarModel.cabin_zone(Vector3(0.0, 0.95, -0.8), Vector3.BACK) == &"dash",
		"each part of the cabin is where it is in a car")


func _test_cabin() -> void:
	var scene := load(PlayerCarModel.MODEL) as PackedScene
	var raw := scene.instantiate()
	var before := 0
	for mesh: MeshInstance3D in raw.find_children("kiri86_Interior", "MeshInstance3D", true, false):
		before += _triangles(mesh.mesh)
	raw.free()
	var model := PlayerCarModel.make(2.6)
	root.add_child(model)
	var after := 0
	for key: StringName in [&"seats", &"bolsters", &"floor", &"headliner", &"doors", &"dash"]:
		var part := model.cabin_parts.get(key) as MeshInstance3D
		var m := part.material_override as StandardMaterial3D if part else null
		expect(part != null and _triangles(part.mesh) > 0 and m != null and m.albedo_texture != null
			and m.normal_enabled and m.normal_texture != null and m.roughness_texture != null
			and part.get_parent() == model.body,
			"the cabin's %s are a textured part of their own, leaning with the body" % key)
		if part:
			after += _triangles(part.mesh)
	for cut: Dictionary in [model.mirror_glass, model.mirror_housing]:
		after += _triangles((cut[&"rear"] as MeshInstance3D).mesh)
	expect(before > 3000 and after == before,
		"the cabin's parts hold every triangle the interior had: %d of %d" % [after, before])
	var wheel := model.steering_wheel as MeshInstance3D
	expect((wheel.material_override as StandardMaterial3D).resource_name == "cabin_wheel",
		"the steering wheel is leather")
	model.free()


func _triangles(mesh: Mesh) -> int:
	var count := 0
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		var index: Variant = arrays[Mesh.ARRAY_INDEX]
		count += (index as PackedInt32Array).size() / 3 if index != null \
			else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return count


func _test_live() -> void:
	var car: Node3D = CAR.instantiate()
	root.add_child(car)
	var model: PlayerCarModel = car.model
	var view: Node3D = car.driver_view
	expect(model != null and view.position.distance_to(model.steering_centre
		+ CAR_SCRIPT.EYE_FROM_WHEEL) < 0.001 and view.position.y > 1.0 and view.position.y < 1.4,
		"the driver sits behind the steering wheel, eyes at %.2f m" % view.position.y)
	if model == null:
		car.queue_free()
		await process_frame
		return

	model.drive(0.5, 3.0, 1.0, true, false, true, false, true)
	expect(model.wheel_turn() > deg_to_rad(20.0), "steering left turns the front wheels left: %.0f°"
		% rad_to_deg(model.wheel_turn()))
	expect(model.is_lit(&"blinkers_left") and not model.is_lit(&"blinkers_right")
		and model.is_lit(&"brake") and model.is_lit(&"headlights") and not model.is_lit(&"reverse"),
		"the lights show the left indicator, the brake, and the headlights")
	model.drive(0.1, 0.0, 0.0, false, false, false, true, false)
	expect(is_zero_approx(model.wheel_turn()) and model.is_lit(&"reverse")
		and not model.is_lit(&"blinkers_left"), "and change as the car does")

	# Driven for real: the instruments and the indicator follow the car.
	car.probe.indicator = VehicleProbe.Indicator.RIGHT
	car.probe.headlights = VehicleProbe.Toggle.ON
	car.held_controls = {throttle = 1.0}
	await frames(60)
	var instruments: InstrumentCluster = car.instruments
	expect(instruments.speed_kmh > 10.0 and is_equal_approx(instruments.speed_kmh,
		car.current_speed * 3.6), "the speedometer reads the car's speed: %.0f km/h"
		% instruments.speed_kmh)
	expect(instruments.headlights and not instruments.left_on, "the headlights tell-tale is lit")
	expect(instruments.rpm > CarDrivetrain.IDLE_RPM and instruments.gear == str(car.gear),
		"the rev counter and the gear follow the drivetrain: %.0f rpm, %s"
		% [instruments.rpm, instruments.gear])
	expect(absf(instruments.speed_needle - instruments.speed_kmh) < 3.0,
		"the speed needle follows the speed: %.1f, %.1f"
		% [instruments.speed_needle, instruments.speed_kmh])
	var beams: Array = model.beams.filter(func(b: SpotLight3D) -> bool: return b.visible)
	expect(model.beams.size() == 2 and beams.size() == 2
		and model.beams.all(func(b: SpotLight3D) -> bool: return b.position.z < -1.5),
		"the headlamps cast their beams, from the front of the car")
	car.probe.headlights = VehicleProbe.Toggle.OFF
	await physics_frame
	expect(model.beams.all(func(b: SpotLight3D) -> bool: return not b.visible),
		"and go dark with the headlights")
	car.probe.headlights = VehicleProbe.Toggle.ON
	var seen_on := false
	var seen_off := false
	for i in 50:
		await physics_frame
		if instruments.right_on:
			seen_on = true
		else:
			seen_off = true
	expect(seen_on and seen_off, "the right indicator arrow blinks")
	car.queue_free()
	await process_frame


func _test_instruments() -> void:
	expect(is_equal_approx(InstrumentCluster.needle_angle(0.0), InstrumentCluster.START)
		and is_equal_approx(InstrumentCluster.needle_angle(InstrumentCluster.TOP_SPEED),
		InstrumentCluster.START + InstrumentCluster.SWEEP)
		and is_equal_approx(InstrumentCluster.needle_angle(999.0),
		InstrumentCluster.START + InstrumentCluster.SWEEP),
		"the needle sweeps from nought to the top speed and stops there")
	var cluster := InstrumentCluster.new()
	var highest := 0.0
	for i in 120:
		cluster.show_state(1.0 / 60.0, 100.0, 3000.0, "3", false, false, false, false, false)
		highest = maxf(highest, cluster.speed_needle)
	expect(absf(cluster.speed_needle - 100.0) < 0.1 and highest <= 100.0001
		and absf(cluster.rpm_needle - 3000.0) < 1.0,
		"the needles settle on their readings without overshooting: %.2f" % highest)
	cluster.free()
	expect(CAR_SCRIPT.blink_on(0.0) and CAR_SCRIPT.blink_on(0.3) and not CAR_SCRIPT.blink_on(0.4)
		and CAR_SCRIPT.blink_on(0.75), "an indicator is lit, then dark, in turn")
