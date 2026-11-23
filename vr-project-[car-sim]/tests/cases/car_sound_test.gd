extends TestCase
## The car's sounds ([CarSound]): the recordings in place, the engine's loops crossfading and
## pitching with the revolutions, the tyres rolling louder with speed, their three voices (scrub,
## squeal, skid) each from its own slip and quiet in ordinary driving, the indicator ticking with
## its blink, and the car playing them as it drives.



func run() -> void:
	_test_mix()
	_test_voices()
	_test_streams()
	await _test_on_car()
	await _test_drives()


func _test_mix() -> void:
	var idle := CarSound.engine_mix(CarSound.LOW_RPM, 0.0)
	var high := CarSound.engine_mix(CarSound.HIGH_RPM, 0.0)
	expect(idle.low_db > idle.high_db + 30.0 and high.high_db > high.low_db + 30.0,
		"the slow loop plays at idle, the fast one at high revolutions")
	expect(is_equal_approx(idle.low_pitch, 1.0) and is_equal_approx(high.high_pitch, 1.0),
		"each loop plays at its own pitch at its own revolutions")
	var half := CarSound.engine_mix((CarSound.LOW_RPM + CarSound.HIGH_RPM) * 0.5, 0.0)
	expect(absf(half.low_db - half.high_db) < 0.01, "halfway, they play alike")
	expect(CarSound.engine_mix(2000.0, 1.0).low_db > CarSound.engine_mix(2000.0, 0.0).low_db + 5.0,
		"the throttle makes the engine louder")
	expect(CarSound.roll_db(0.0) <= -80.0, "standing still, the tyres make no sound")
	expect(CarSound.roll_db(20.0) > CarSound.roll_db(5.0) + 10.0
		and CarSound.roll_db(200.0) <= CarSound.ROLL_MAX_DB,
		"rolling, they rumble louder with speed, to a limit")


## The voices wanted with every wheel at slip ratio share [param sx] and slip angle share
## [param sy] at [param speed] m/s.
func _voices(sx: float, sy: float, speed := 20.0) -> Dictionary:
	var spec := CarSpec.new().packed()
	var r := sx * spec[CarSpec.PEAK_RATIO]
	var a := atan(sy * tan(spec[CarSpec.PEAK_ANGLE]))
	return CarSound.tyre_voices(spec, PackedFloat64Array([-r, -r, -r, -r]),
		PackedFloat64Array([a, a, a, a]), PackedVector2Array([Vector2.ONE * 3000.0,
		Vector2.ONE * 3000.0, Vector2.ONE * 3000.0, Vector2.ONE * 3000.0]),
		PackedByteArray([1, 1, 1, 1]), speed)


func _test_voices() -> void:
	var cruising := _voices(0.05, 0.05)
	expect(cruising.scrub == 0.0 and cruising.squeal == 0.0 and cruising.skid == 0.0,
		"cruising, the tyres only roll")
	var turning := _voices(0.0, 0.7)
	expect(turning.scrub > 0.3 and turning.squeal == 0.0, "turning, they scrub but do not squeal")
	expect(_voices(0.0, 1.0).squeal == 0.0, "at their peak slip angle, still no squeal")
	expect(_voices(0.0, 2.0).squeal > 0.0
		and _voices(0.0, 2.0).squeal < _voices(0.0, 2.8).squeal,
		"sliding sideways past it, they squeal, louder the further they slide")
	var braking := _voices(1.2, 0.0)
	expect(braking.skid == 0.0 and braking.squeal == 0.0,
		"braking as hard as the anti-lock brakes allow, neither squeal nor skid")
	var locked := _voices(10.0, 0.0)
	expect(locked.skid == 1.0 and locked.squeal == 0.0, "locked, they skid, and do not squeal")
	expect(_voices(10.0, 3.0, 2.0).skid == 0.0 and _voices(10.0, 3.0, 2.0).squeal == 0.0,
		"at walking pace nothing slides loud enough to hear")
	expect(CarSound.envelope(0.0, 1.0, 1.0 / 60.0, CarSound.SKID_ATTACK, CarSound.VOICE_RELEASE)
		< CarSound.VOICE_FLOOR, "one step's spike of slip passes unheard")
	expect(CarSound.voice_db(0.0, -30.0, -10.0) <= -80.0
		and CarSound.voice_db(1.0, -30.0, -10.0) == -10.0, "a voice is silent at 0, loud at 1")
	var spec := CarSpec.new().packed()
	var zero := PackedFloat64Array([0.0, 0.0, 0.0, 0.0])
	var push := PackedVector2Array([Vector2.ONE, Vector2.ONE, Vector2.ONE, Vector2.ONE])
	var half := CarSound.tyre_voices(spec, zero, zero, push, PackedByteArray([1, 1, 1, 1]), 10.0,
		PackedByteArray([1, 0, 1, 0]))
	var lifted := CarSound.tyre_voices(spec, zero, zero, push, PackedByteArray([1, 0, 0, 0]), 10.0,
		PackedByteArray([1, 0, 0, 0]))
	expect(half.loose == 0.5 and lifted.loose == 1.0,
		"the loose ground's share counts the wheels standing on it")
	var sound := CarSound.new()
	sound.follow(1000.0, 0.0, false, false, {}, 15.0, CarDynamics.EngineState.RUNNING, true)
	for i in 20:
		sound.follow(1000.0, 0.0, false, false, {}, 15.0, CarDynamics.EngineState.RUNNING, false)
	expect(sound.voices.skid < CarSound.VOICE_FLOOR, "a lone anti-lock blip makes no skid")
	for i in 60:
		sound.follow(1000.0, 0.0, false, false, {}, 15.0, CarDynamics.EngineState.RUNNING, i % 2 == 0)
	expect(absf(sound.voices.skid - CarSound.ABS_SKID) < 0.05,
		"the anti-lock brakes at work skid softly: %.2f" % sound.voices.skid)
	sound.free()


func _test_streams() -> void:
	var loop := CarSound.engine_loop(CarSound.LOW_RPM, 1)
	expect(loop.loop_mode == AudioStreamWAV.LOOP_FORWARD and loop.get_length() > 0.5
		and loop.data.size() == loop.loop_end * 2, "the engine is a seamless loop: %.2f s"
		% loop.get_length())
	expect(CarSound.click(2000.0, 0.01).get_length() < 0.05, "a tick is short")
	for wav: AudioStreamWAV in [CarSound.squeal_loop(), CarSound.skid_loop(),
			CarSound.scrub_loop(), CarSound.roll_loop()]:
		var last := wav.data.size() - 2
		var seam := absf(wav.data.decode_s16(last) - wav.data.decode_s16(0)) / 32768.0
		var step := 0.0
		for i in range(2, 4000, 2):
			step = maxf(step, absf(wav.data.decode_s16(i) - wav.data.decode_s16(i - 2)) / 32768.0)
		expect(wav.loop_mode == AudioStreamWAV.LOOP_FORWARD and seam <= step * 1.5,
			"a noise loop joins up as smoothly as it flows: seam %.3f, largest step %.3f"
			% [seam, step])


func _test_on_car() -> void:
	var floor := ground()
	var car: Node3D = spawn_car()
	await physics_frame
	var sound: CarSound = car.sound
	expect(sound != null and sound.engine_low.playing and sound.engine_high.playing,
		"the engine runs")
	expect(sound.engine_low.stream.resource_path == CarSound.ENGINE_IDLE
		and sound.roll.stream.resource_path == CarSound.ROAD
		and sound.tick.stream.resource_path == CarSound.TICK_ON
		and sound.scrub.stream.resource_path == CarSound.SCRUB_ROAD
		and sound.roll_loose.stream.resource_path == CarSound.ROAD_LOOSE
		and sound.scrub_loose.stream.resource_path == CarSound.SCRUB_LOOSE
		and sound.slide_loose.stream.resource_path == CarSound.SLIDE_LOOSE,
		"the engine at idle, each surface's rolling, scrub and slide, and the indicator play their recordings")
	for player: AudioStreamPlayer3D in [sound.engine_low, sound.roll, sound.scrub, sound.roll_loose,
			sound.scrub_loose, sound.slide_loose]:
		var wav := player.stream as AudioStreamWAV
		expect(wav != null and wav.loop_mode == AudioStreamWAV.LOOP_FORWARD
			and wav.get_length() >= 4.9, "%s loops over %.1f s" % [player.name, wav.get_length()])
	expect(AudioServer.get_bus_index(CarSound.BUS) != -1 and sound.engine_low.bus == CarSound.BUS,
		"on the car's audio bus")
	car.held_controls = {throttle = 1.0, select = "D"}
	for i in 90:
		await physics_frame
	expect(is_equal_approx(sound.engine_low.pitch_scale,
		clampf(car.signals.rpm / CarSound.LOW_RPM, 0.5, 4.0)),
		"the engine's pitch follows the crank sensor's revolutions")
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


## Scripted drives on a wide floor: what each voice reaches, heard, in ordinary driving and in
## hard driving.
func _test_drives() -> void:
	# A lane change at 50 km/h: about 2.7° at the wheels, some 3 m/s² across. The steering is the
	# driver's alone, so a calm one is a small turn of the wheel.
	var calm := await _drive(13.9, func(t: float) -> Dictionary:
		return {steer = 0.08 if t < 0.6 else (-0.08 if t < 1.2 else 0.0)}, 2.5)
	expect(calm.squeal < CarSound.VOICE_FLOOR and calm.skid < CarSound.VOICE_FLOOR,
		"a lane change at 50 km/h: no squeal, no skid (%.2f, %.2f)" % [calm.squeal, calm.skid])
	var junction := await _drive(5.6, func(_t: float) -> Dictionary: return {steer = 1.0}, 3.0)
	expect(junction.squeal < CarSound.VOICE_FLOOR and junction.scrub > 0.5,
		"full lock at 20 km/h: the tyres scrub, no squeal (%.2f)" % junction.squeal)
	var hard := await _drive(8.3, func(_t: float) -> Dictionary: return {steer = 1.0}, 3.0)
	expect(hard.squeal > 0.3, "full lock at 30 km/h: they squeal (%.2f)" % hard.squeal)
	var gentle := await _drive(16.7, func(_t: float) -> Dictionary:
		return {brake = 0.4, hold = false}, 3.0)
	expect(gentle.squeal < CarSound.VOICE_FLOOR and gentle.skid < CarSound.VOICE_FLOOR,
		"a gentle stop from 60 km/h is quiet (%.2f, %.2f)" % [gentle.squeal, gentle.skid])
	var stop := await _drive(16.7, func(_t: float) -> Dictionary:
		return {brake = 1.0, hold = false}, 3.0)
	expect(stop.skid > 0.2 and stop.squeal < CarSound.VOICE_FLOOR,
		"a full stop from 60 km/h skids under the anti-lock brakes, no squeal (%.2f, %.2f)"
		% [stop.skid, stop.squeal])
	var slide := await _drive(13.9, func(_t: float) -> Dictionary:
		return {steer = 1.0, handbrake = 1.0, hold = false}, 1.5)
	expect(slide.squeal > 0.5 and slide.skid > 0.5 and slide.squeal_db > -20.0
		and slide.slide_loose_db < -60.0,
		"a handbrake turn on asphalt squeals and skids (%.2f, %.2f), no gravel"
		% [slide.squeal, slide.skid])
	var grass := await _drive(13.9, func(_t: float) -> Dictionary: return {}, 2.0, &"ground")
	expect(grass.loose > 0.95 and grass.roll_loose_db > grass.roll_db + 30.0
		and grass.slide_loose_db < -60.0 and grass.squeal_db < -60.0,
		"cruising on grass rolls as on dirt, no road, no slide, no squeal (%.1f dB, %.1f dB)"
		% [grass.roll_loose_db, grass.roll_db])
	var spin := await _drive(13.9, func(_t: float) -> Dictionary:
		return {steer = 1.0, handbrake = 1.0, hold = false}, 1.5, &"ground")
	expect(spin.slide_loose_db > -20.0 and spin.squeal_db < -60.0 and spin.skid_db < -60.0,
		"a handbrake turn on grass sprays gravel, never squeals (%.1f dB, squeal %.1f dB)"
		% [spin.slide_loose_db, spin.squeal_db])


## Drives a fresh car up to [param speed] m/s, then for [param seconds] with the controls
## [param legs] gives for each moment, holding the speed unless they say [code]hold = false[/code].
## Returns each voice's loudest heard share, the loose share at the end, and each tyre player's
## loudest volume (dB), after the run-up, on a floor of [param surface].
func _drive(speed: float, legs: Callable, seconds: float, surface := &"asphalt") -> Dictionary:
	var floor := ground(3000.0, surface)
	var car: Node3D = spawn_car()
	await physics_frame
	car.held_controls = {throttle = 1.0, select = "D"}
	var guard := 0
	while car.current_speed < speed and guard < 1200:
		await physics_frame
		guard += 1
	# Past the run-up's own wheelspin.
	car.held_controls = {throttle = 0.3, select = "D"}
	for i in 30:
		await physics_frame
	var most := {scrub = 0.0, squeal = 0.0, skid = 0.0, squeal_db = -80.0, skid_db = -80.0,
		slide_loose_db = -80.0, roll_db = -80.0, roll_loose_db = -80.0}
	for k in int(seconds * 60.0):
		var c: Dictionary = legs.call(k / 60.0)
		var throttle := 0.0
		if c.get("hold", true):
			throttle = clampf((speed - car.current_speed) * 0.6 + 0.25, 0.0, 1.0)
		car.held_controls = {throttle = throttle, brake = c.get("brake", 0.0),
			steer = c.get("steer", 0.0), handbrake = c.get("handbrake", 0.0), select = "D"}
		await physics_frame
		var sound: CarSound = car.sound
		for v in sound.voices:
			most[v] = maxf(most[v], sound.voices[v])
		for v in ["squeal", "skid", "slide_loose", "roll", "roll_loose"]:
			var player: AudioStreamPlayer3D = sound.get(v)
			most[v + "_db"] = maxf(most[v + "_db"], player.volume_db)
		most.loose = sound.loose
	car.queue_free()
	floor.queue_free()
	await process_frame
	return most
