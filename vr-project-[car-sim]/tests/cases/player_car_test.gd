extends TestCase
## The player's car as drawn: the Kiri '86 fitted to the car, the driver seated behind its
## steering wheel, its live parts (wheels, steering wheel, lights), and the instruments, all
## following the car's state.

const CAR := preload("res://scenarios/scenes/debug_car.tscn")
const CAR_SCRIPT := preload("res://scenarios/scenes/debug_car.gd")


func run() -> void:
	_test_fit()
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
	model.free()


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
	expect(CAR_SCRIPT.blink_on(0.0) and CAR_SCRIPT.blink_on(0.3) and not CAR_SCRIPT.blink_on(0.4)
		and CAR_SCRIPT.blink_on(0.75), "an indicator is lit, then dark, in turn")
