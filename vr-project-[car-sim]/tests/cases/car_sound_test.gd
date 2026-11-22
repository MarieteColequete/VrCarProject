extends TestCase
## The car's sounds ([CarSound]): the engine's loops crossfading and pitching with the revolutions,
## the tyres squealing only near their grip, the indicator ticking with its blink, and the car
## playing them as it drives.

const CAR := preload("res://scenarios/scenes/debug_car.tscn")


func run() -> void:
	_test_mix()
	_test_streams()
	await _test_on_car()


func _test_mix() -> void:
	var idle := CarSound.engine_mix(CarSound.LOW_RPM, 0.0)
	var high := CarSound.engine_mix(CarSound.HIGH_RPM, 0.0)
	expect(idle.low_db > idle.high_db + 30.0 and high.high_db > high.low_db + 30.0,
		"the slow loop plays at idle, the fast one at high revolutions")
	expect(is_equal_approx(idle.low_pitch, 1.0) and is_equal_approx(high.high_pitch, 1.0),
		"each loop plays at its own pitch at its own revolutions")
	var half := CarSound.engine_mix(2500.0, 0.0)
	expect(absf(half.low_db - half.high_db) < 0.01, "halfway, they play alike")
	expect(CarSound.engine_mix(2000.0, 1.0).low_db > CarSound.engine_mix(2000.0, 0.0).low_db + 5.0,
		"the throttle makes the engine louder")
	expect(CarSound.squeal_db(0.4, 20.0) <= -80.0, "well within their grip, the tyres are quiet")
	expect(CarSound.squeal_db(1.0, 3.0) <= -80.0, "and slowly, too")
	expect(CarSound.squeal_db(1.0, 20.0) > -20.0, "at the grip, fast, they squeal")


func _test_streams() -> void:
	var loop := CarSound.engine_loop(CarSound.LOW_RPM, 1)
	expect(loop.loop_mode == AudioStreamWAV.LOOP_FORWARD and loop.get_length() > 0.5
		and loop.data.size() == loop.loop_end * 2, "the engine is a seamless loop: %.2f s"
		% loop.get_length())
	expect(CarSound.click(2000.0, 0.01).get_length() < 0.05, "a tick is short")


func _test_on_car() -> void:
	var floor := ground()
	var car: Node3D = CAR.instantiate()
	root.add_child(car)
	await physics_frame
	var sound: CarSound = car.sound
	expect(sound != null and sound.engine_low.playing and sound.engine_high.playing,
		"the engine runs")
	expect(AudioServer.get_bus_index(CarSound.BUS) != -1 and sound.engine_low.bus == CarSound.BUS,
		"on the car's audio bus")
	car.held_controls = {throttle = 1.0, select = "D"}
	for i in 90:
		await physics_frame
	expect(is_equal_approx(sound.engine_low.pitch_scale,
		clampf(car.rpm / CarSound.LOW_RPM, 0.5, 4.0)), "the engine's pitch follows the revolutions")
	var before := sound.ticks
	car.probe.indicator = VehicleProbe.Indicator.LEFT
	for i in 90:
		await physics_frame
	var ticks := sound.ticks - before
	# 1.5 s at 0.35 s lit and 0.35 s dark: four or five edges.
	expect(ticks >= 4 and ticks <= 5, "the indicator ticks on and off as it blinks: %d" % ticks)
	car.queue_free()
	floor.queue_free()
	await process_frame
