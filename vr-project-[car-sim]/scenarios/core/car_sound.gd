class_name CarSound
extends Node3D
## The car's sounds, heard in the cabin: the engine, the indicator's tick, the tyres rolling on the
## road, and the tyres' three voices ([method tyre_voices]): a scrub that grows as they work
## toward their grip, a squeal when they slide sideways past it, and a skid, lower and rougher,
## when they lock or spin, pulsing while the anti-lock brakes work; and a thump when a tyre meets a
## kerb. Each surface sounds its own: on the roads the rolling is a car on asphalt and the scrub
## its tyres' roar; on the loose ground (grass and dirt) the rolling is a car on a dirt road, the
## scrub tyres crunching gravel, and any slide, sideways or locked, gravel spraying, never a
## squeal. The two crossfade by the share of wheels on each. The engine at
## idle, the road and the indicator's relay are recordings (assets/freesound/, CC0), each with a
## sound made here in its place when its file is missing; the rest is made here when the car is
## built. The engine is two loops, one slow and one fast, crossfaded and pitched with the
## revolutions, louder on the throttle; the fast one is made here, a four-cylinder's firing pulses
## and their harmonics. They play on the [constant BUS] audio bus. Nothing here takes part in the
## simulation.

const BUS := &"Car"
const MIX_RATE := 22050
## The recordings, each cut by tools/car_recordings.gd to the loudness of the sound it replaces.
const ENGINE_IDLE := "res://assets/freesound/engine_idle/engine_idle.wav"
const ROAD := "res://assets/freesound/road_interior/road_interior.wav"
const ROAD_LOOSE := "res://assets/freesound/road_dirt/road_dirt.wav"
const SCRUB_ROAD := "res://assets/freesound/tyres_asphalt/tyres_asphalt.wav"
const SCRUB_LOOSE := "res://assets/freesound/tyres_gravel/tyres_gravel.wav"
const SLIDE_LOOSE := "res://assets/freesound/slide_gravel/slide_gravel.wav"
const TICK_ON := "res://assets/freesound/indicator/indicator_on.wav"
const TICK_OFF := "res://assets/freesound/indicator/indicator_off.wav"
## The revolutions the engine's two loops are made at: the slow one at the idle recording's, read
## from its firing harmonics, 46 Hz apart.
const LOW_RPM := 1380.0
const HIGH_RPM := 4000.0
## The engine's loudness, decibels, off the throttle and on it, and while a gear changes.
const ENGINE_COAST_DB := -14.0
const ENGINE_FULL_DB := -4.0
const SHIFT_DIP_DB := -6.0
## How much quieter the engine is while the starter turns it over, dB.
const CRANK_DB := -12.0
## The tyres' voices, each a share from 0 to 1 of the slip that drives it, measured in scripted
## drives (Research/car-audio/README.md). The scrub follows the combined slip
## ([method TyreModel.usage]) from [constant SCRUB_FROM] to [constant SCRUB_FULL]. The squeal
## follows the slip angle over the peak's, from [constant SQUEAL_FROM] to [constant SQUEAL_FULL]:
## a full key steer at 20 km/h sits near 1 (1.4 at worst) and stays quiet, a full key steer at
## 50 km/h near 1.7 and sings softly, at 30 km/h near 2.1 and louder, a slide at 3 or more at full
## voice. The skid follows the slip ratio over the peak's, from [constant SKID_FROM], well past
## where the anti-lock brakes ease off (1.2) and the brief wheelspin of a full-throttle gear change,
## to [constant SKID_FULL].
const SCRUB_FROM := 0.3
const SCRUB_FULL := 1.2
const SQUEAL_FROM := 1.5
const SQUEAL_FULL := 3.0
const SKID_FROM := 2.0
const SKID_FULL := 6.0
## The speeds, m/s, below which the tyres neither squeal nor skid, and from which they do fully: at
## walking pace a braked wheel's slip reads large though nothing slides.
const SLIDE_SPEED_FROM := 4.0
const SLIDE_SPEED_FULL := 8.0
## The skid while the anti-lock brakes work: its share, and how often it pulses, Hz.
const ABS_SKID := 0.35
const ABS_PULSE_HZ := 12.0
## How the anti-lock brakes count as working: they act in bursts, step to step, through a stop, so
## their activity is smoothed (rising in [constant ABS_ATTACK] seconds, falling in
## [constant ABS_RELEASE]) and heard from [constant ABS_FROM]; a lone blip stays unheard.
const ABS_ATTACK := 0.1
const ABS_RELEASE := 0.4
const ABS_FROM := 0.4
## The least share of a voice that is heard; below it the voice is silent.
const VOICE_FLOOR := 0.08
## Seconds each voice takes to rise and to fall by most of the way, so one step's spike of slip
## passes unheard.
const VOICE_ATTACK := 0.15
const SKID_ATTACK := 0.25
const VOICE_RELEASE := 0.25
## Seconds the crossfade between surfaces takes most of the way.
const SURFACE_SWAP := 0.15
## Each voice's loudness, dB, as it begins and at full voice.
const SCRUB_QUIET_DB := -30.0
const SCRUB_LOUD_DB := -16.0
const SLIDE_QUIET_DB := -26.0
const SLIDE_LOUD_DB := -8.0
const SQUEAL_QUIET_DB := -30.0
const SQUEAL_LOUD_DB := -13.0
const SKID_QUIET_DB := -28.0
const SKID_LOUD_DB := -10.0
## The squeal's pitch from its start to full voice: the harder the slide, the higher it sings.
const SQUEAL_LOW_PITCH := 0.9
const SQUEAL_HIGH_PITCH := 1.1
## The tyres' rumble on the road: its loudness, dB, at [constant ROLL_SPEED] metres per second,
## rising 6 dB for each doubling of speed to at most [constant ROLL_MAX_DB]; silent standing still.
const ROLL_SPEED := 20.0
const ROLL_DB := -20.0
const ROLL_MAX_DB := -12.0

var engine_low: AudioStreamPlayer3D
var engine_high: AudioStreamPlayer3D
var squeal: AudioStreamPlayer3D
var skid: AudioStreamPlayer3D
var scrub: AudioStreamPlayer3D
var roll: AudioStreamPlayer3D
## The loose ground's: its rolling, its scrub, and its slide.
var roll_loose: AudioStreamPlayer3D
var scrub_loose: AudioStreamPlayer3D
var slide_loose: AudioStreamPlayer3D
var tick: AudioStreamPlayer3D
var thump: AudioStreamPlayer3D

## How many times the indicator has ticked, on and off.
var ticks := 0
## The tyres' voices as heard, smoothed: [code]{scrub, squeal, skid}[/code], each 0 to 1.
var voices := {scrub = 0.0, squeal = 0.0, skid = 0.0}
## The share of the wheels on loose ground, smoothed, 0 to 1.
var loose := 0.0

var _tick_on: AudioStream
var _tick_off: AudioStream
var _lit := false
var _clock := 0.0
## The anti-lock brakes' smoothed activity, 0 to 1.
var abs_activity := 0.0


## The sounds made by code, by name ([method _made]).
static var _cache := {}


func _init() -> void:
	name = "Sound"
	_ensure_bus()
	engine_low = _player("EngineLow", _recording(ENGINE_IDLE, engine_loop.bind(LOW_RPM, 11)))
	engine_high = _player("EngineHigh", _made(&"engine_high", engine_loop.bind(HIGH_RPM, 23)))
	squeal = _player("Squeal", _made(&"squeal", squeal_loop))
	skid = _player("Skid", _made(&"skid", skid_loop))
	scrub = _player("Scrub", _recording(SCRUB_ROAD, scrub_loop))
	roll = _player("Roll", _recording(ROAD, roll_loop))
	roll_loose = _player("RollLoose", _recording(ROAD_LOOSE, roll_loop))
	scrub_loose = _player("ScrubLoose", _recording(SCRUB_LOOSE, scrub_loop))
	slide_loose = _player("SlideLoose", _recording(SLIDE_LOOSE, skid_loop))
	_tick_on = _recording(TICK_ON, click.bind(2600.0, 0.012))
	_tick_off = _recording(TICK_OFF, click.bind(1700.0, 0.010))
	tick = _player("Tick", _tick_on)
	thump = _player("Thump", knock())
	# The indicator relay sits behind the dashboard, the engine ahead of it.
	engine_low.position = Vector3(0.0, 0.6, -1.6)
	engine_high.position = engine_low.position
	tick.position = Vector3(-0.3, 0.9, -0.5)
	# The tyres are below and around the driver.
	for player: AudioStreamPlayer3D in _tyre_players():
		player.position = Vector3(0.0, 0.0, -0.4)


func _ready() -> void:
	engine_low.play()
	engine_high.play()
	for player: AudioStreamPlayer3D in _tyre_players():
		player.play()
		player.volume_db = -80.0


func _tyre_players() -> Array[AudioStreamPlayer3D]:
	return [squeal, skid, scrub, roll, roll_loose, scrub_loose, slide_loose]


## Follows the car for a step: the engine at [param rpm] with [param throttle] (0 to 1), dipped
## while [param shifting]; the indicator ticking as [param blink_lit] turns on and off; the tyres
## rolling at [param speed] metres per second with the voices [param tyres] asks, on the share of
## loose ground it gives ([method tyre_voices]), the skid pulsing while [param abs_working], each smoothed over
## [param delta] seconds. The [param engine] ([enum CarDynamics.EngineState]) off is silent, and
## turned over by the starter it chugs low and quiet.
func follow(rpm: float, throttle: float, shifting: bool, blink_lit: bool, tyres: Dictionary,
		speed: float, engine := CarDynamics.EngineState.RUNNING, abs_working := false,
		delta := 1.0 / 60.0) -> void:
	var mix := engine_mix(rpm, throttle)
	var dip := SHIFT_DIP_DB if shifting else 0.0
	match engine:
		CarDynamics.EngineState.OFF:
			dip = -80.0
		CarDynamics.EngineState.CRANKING:
			dip = CRANK_DB
	engine_low.volume_db = mix.low_db + dip
	engine_high.volume_db = mix.high_db + dip
	engine_low.pitch_scale = mix.low_pitch
	engine_high.pitch_scale = mix.high_pitch
	_clock = fmod(_clock + delta, 1.0)
	abs_activity = envelope(abs_activity, 1.0 if abs_working else 0.0, delta, ABS_ATTACK,
		ABS_RELEASE)
	abs_working = abs_activity > ABS_FROM
	var skid_wanted: float = tyres.get("skid", 0.0)
	if abs_working:
		skid_wanted = maxf(skid_wanted, ABS_SKID * clampf((absf(speed) - SLIDE_SPEED_FROM)
			/ (SLIDE_SPEED_FULL - SLIDE_SPEED_FROM), 0.0, 1.0))
	voices.scrub = envelope(voices.scrub, tyres.get("scrub", 0.0), delta, VOICE_ATTACK,
		VOICE_RELEASE)
	voices.squeal = envelope(voices.squeal, tyres.get("squeal", 0.0), delta, VOICE_ATTACK,
		VOICE_RELEASE)
	voices.skid = envelope(voices.skid, skid_wanted, delta, SKID_ATTACK, VOICE_RELEASE)
	loose = envelope(loose, tyres.get("loose", 0.0), delta, SURFACE_SWAP, SURFACE_SWAP)
	var on_road := linear_to_db(maxf(1.0 - loose, 0.0001))
	var on_loose := linear_to_db(maxf(loose, 0.0001))
	var pulse := 0.0
	if abs_working:
		# The brakes let go and bite again: the skid swells and fades with each cycle.
		pulse = linear_to_db(0.35 + 0.65 * absf(sin(PI * ABS_PULSE_HZ * _clock)))
	scrub.volume_db = voice_db(voices.scrub, SCRUB_QUIET_DB, SCRUB_LOUD_DB) + on_road
	scrub_loose.volume_db = voice_db(voices.scrub, SCRUB_QUIET_DB, SCRUB_LOUD_DB) + on_loose
	squeal.volume_db = voice_db(voices.squeal, SQUEAL_QUIET_DB, SQUEAL_LOUD_DB) + on_road
	squeal.pitch_scale = lerpf(SQUEAL_LOW_PITCH, SQUEAL_HIGH_PITCH, voices.squeal)
	skid.volume_db = voice_db(voices.skid, SKID_QUIET_DB, SKID_LOUD_DB) + pulse + on_road
	# Loose ground does not sing: a slide either way sprays gravel.
	slide_loose.volume_db = voice_db(maxf(voices.squeal, voices.skid), SLIDE_QUIET_DB,
		SLIDE_LOUD_DB) + pulse + on_loose
	for player: AudioStreamPlayer3D in [scrub, scrub_loose, slide_loose]:
		player.pitch_scale = roll_pitch(speed)
	roll.volume_db = roll_db(speed) + on_road
	roll_loose.volume_db = roll_db(speed) + on_loose
	roll.pitch_scale = roll_pitch(speed)
	roll_loose.pitch_scale = roll_pitch(speed)
	if blink_lit != _lit:
		_lit = blink_lit
		tick.stream = _tick_on if blink_lit else _tick_off
		tick.play()
		ticks += 1


## A tyre has just met a kerb.
func knock_kerb() -> void:
	thump.play()


## The engine's loops at [param rpm] with [param throttle]: [code]{low_db, high_db, low_pitch,
## high_pitch}[/code], the slow loop fading into the fast one between their revolutions, each
## pitched to the revolutions, louder on the throttle.
static func engine_mix(rpm: float, throttle: float) -> Dictionary:
	var blend := clampf((rpm - LOW_RPM) / (HIGH_RPM - LOW_RPM), 0.0, 1.0)
	var loud := lerpf(ENGINE_COAST_DB, ENGINE_FULL_DB, clampf(throttle, 0.0, 1.0))
	return {low_db = loud + linear_to_db(maxf(1.0 - blend, 0.0001)),
		high_db = loud + linear_to_db(maxf(blend, 0.0001)),
		low_pitch = clampf(rpm / LOW_RPM, 0.5, 4.0), high_pitch = clampf(rpm / HIGH_RPM, 0.25, 2.0)}


## The tyres' voices wanted from the last step: [code]{scrub, squeal, skid, loose}[/code], each 0
## to 1, from each wheel's slip ratio [param ratio], slip angle [param angle] and force
## [param force] ([CarDynamics]), the wheels off the ground ([param grounded] 0) left out, at
## [param speed] m/s; [code]loose[/code] is the share of the wheels on the ground standing on loose
## ground ([param on_loose] 1).
## Each axle's slip is its wheels' weighted by how hard each pushes, so a wheel barely touching
## the road counts little, and the axle slipping more speaks.
static func tyre_voices(spec: PackedFloat64Array, ratio: PackedFloat64Array,
		angle: PackedFloat64Array, force: PackedVector2Array, grounded: PackedByteArray,
		speed: float, on_loose := PackedByteArray([0, 0, 0, 0])) -> Dictionary:
	var along := [0.0, 0.0]
	var standing := 0
	var loose_count := 0
	var across := [0.0, 0.0]
	var weight := [0.0, 0.0]
	for i in 4:
		if not grounded[i]:
			continue
		var axle := 0 if i < 2 else 1
		standing += 1
		loose_count += on_loose[i]
		var w := force[i].length() + 1.0
		along[axle] += absf(ratio[i]) / spec[CarSpec.PEAK_RATIO] * w
		across[axle] += absf(tan(clampf(angle[i], -1.5, 1.5))) / tan(spec[CarSpec.PEAK_ANGLE]) * w
		weight[axle] += w
	var sx := 0.0
	var sy := 0.0
	for axle in 2:
		if weight[axle] > 0.0:
			sx = maxf(sx, along[axle] / weight[axle])
			sy = maxf(sy, across[axle] / weight[axle])
	var sliding := clampf((absf(speed) - SLIDE_SPEED_FROM) / (SLIDE_SPEED_FULL - SLIDE_SPEED_FROM),
		0.0, 1.0)
	var rolling := clampf(absf(speed) / SLIDE_SPEED_FROM, 0.0, 1.0)
	return {scrub = _share(sqrt(sx * sx + sy * sy), SCRUB_FROM, SCRUB_FULL) * rolling,
		squeal = _share(sy, SQUEAL_FROM, SQUEAL_FULL) * sliding,
		skid = _share(sx, SKID_FROM, SKID_FULL) * sliding,
		loose = float(loose_count) / standing if standing > 0 else 0.0}


## [param value]'s share of the way from [param from] to [param full], 0 to 1.
static func _share(value: float, from: float, full: float) -> float:
	return clampf((value - from) / (full - from), 0.0, 1.0)


## [param current] moved toward [param target] over [param delta] seconds, most of the way in
## [param attack] seconds rising and [param release] falling.
static func envelope(current: float, target: float, delta: float, attack: float,
		release: float) -> float:
	var tau := attack if target > current else release
	return lerpf(current, target, 1.0 - exp(-delta / tau))


## A voice at [param level] (0 to 1) in decibels: silent below [constant VOICE_FLOOR],
## [param quiet] as it begins and
## [param loud] at full voice.
static func voice_db(level: float, quiet: float, loud: float) -> float:
	if level < VOICE_FLOOR:
		return -80.0
	return lerpf(quiet, loud, clampf(level, 0.0, 1.0))


## How loud the tyres rumble on the road at [param speed] metres per second, decibels.
static func roll_db(speed: float) -> float:
	var v := absf(speed)
	if v < 0.3:
		return -80.0
	return minf(ROLL_DB + linear_to_db(v / ROLL_SPEED), ROLL_MAX_DB)


## The rumble's pitch at [param speed]: a little higher the faster the tread turns.
static func roll_pitch(speed: float) -> float:
	return clampf(0.75 + absf(speed) / 60.0, 0.75, 1.5)


## A seamless loop of a four-cylinder engine at [param rpm]: a firing pulse twice a turn, each with
## its own small variation from [param seed], the pulses' harmonics, and some rumble.
static func engine_loop(rpm: float, seed: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var fire := rpm / 60.0 * 2.0
	# An even count of firings, so the half-order harmonics join up too.
	var cycles := maxi(roundi(fire * 0.6) * 2, 8)
	var samples := roundi(cycles * MIX_RATE / fire)
	var per := float(samples) / cycles
	var strengths := PackedFloat32Array()
	for i in cycles:
		strengths.append(rng.randf_range(0.8, 1.0))
	var data := PackedFloat32Array()
	data.resize(samples)
	var rumble := 0.0
	for i in samples:
		var cycle := int(i / per)
		var phase := fmod(i, per) / per
		# A sharp pulse each firing, ringing down.
		var pulse := exp(-phase * 7.0) * sin(phase * TAU * 3.0) * strengths[cycle]
		var tone := 0.0
		for k in range(1, 6):
			tone += sin(TAU * fire * k * 0.5 * i / MIX_RATE) / (k * 1.6)
		rumble = lerpf(rumble, rng.randf_range(-1.0, 1.0), 0.08)
		data[i] = pulse * 0.55 + tone * 0.25 + rumble * 0.2
	return _wav(data, true)


## A loop of tyres squealing: rubber stick-slipping on the road, which rings the tread at a few
## unrelated resonances. Noise through narrow band-pass filters at those resonances, each
## wandering in strength and roughened by the stick-slip's flutter, with a little broadband scrub
## under it. Noise, never a pure tone, so it rasps like rubber rather than whistling.
static func squeal_loop() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var length := MIX_RATE * 2
	var noise := _noise(rng, length + LOOP_FADE)
	# The tread's resonances, hertz, their filters' sharpness, and their shares of the sound.
	var rings := [[1180.0, 14.0, 1.0], [1710.0, 12.0, 0.7], [2460.0, 11.0, 0.45],
		[3350.0, 9.0, 0.25]]
	var data := PackedFloat32Array()
	data.resize(noise.size())
	for ring: Array in rings:
		var band := _band_pass(noise, ring[0], ring[1])
		var wander := _smooth_noise(rng, noise.size(), 3.0)
		for i in noise.size():
			data[i] += band[i] * ring[2] * (0.6 + 0.4 * wander[i])
	var flutter := _smooth_noise(rng, noise.size(), 40.0)
	var scrub := _band_pass(noise, 4500.0, 1.2)
	for i in noise.size():
		data[i] = data[i] * (0.75 + 0.25 * flutter[i]) + scrub[i] * 0.08
	return _wav(_seamless(_normalised(data, 0.8), length), true)


## A loop of tyres skidding, locked or spinning: rubber dragged along the road, juddering as it
## sticks and tears free. Broad bands of noise lower than the squeal's, under a coarse flutter,
## with a dull roar beneath; no ring stands out, so it grinds rather than sings.
static func skid_loop() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var length := MIX_RATE * 2
	var noise := _noise(rng, length + LOOP_FADE)
	var bands := [[450.0, 4.0, 1.0], [800.0, 5.0, 0.8], [1300.0, 6.0, 0.5], [2600.0, 2.0, 0.2]]
	var data := PackedFloat32Array()
	data.resize(noise.size())
	for band: Array in bands:
		var part := _band_pass(noise, band[0], band[1])
		var wander := _smooth_noise(rng, noise.size(), 5.0)
		for i in noise.size():
			data[i] += part[i] * band[2] * (0.65 + 0.35 * wander[i])
	var judder := _smooth_noise(rng, noise.size(), 70.0)
	var tear := _smooth_noise(rng, noise.size(), 18.0)
	var roar := _band_pass(noise, 160.0, 0.8)
	for i in noise.size():
		data[i] = data[i] * (0.55 + 0.3 * judder[i] + 0.15 * tear[i]) + roar[i] * 0.5
	return _wav(_seamless(_normalised(data, 0.8), length), true)


## A loop of the tread scrubbing as it works: a soft, even hiss with no rings in it, the friction
## always under a car that turns or brakes.
static func scrub_loop() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 17
	var length := MIX_RATE * 2
	var noise := _noise(rng, length + LOOP_FADE)
	var low := _band_pass(noise, 1400.0, 0.7)
	var high := _band_pass(noise, 3200.0, 0.8)
	var data := PackedFloat32Array()
	data.resize(noise.size())
	for i in noise.size():
		data[i] = low[i] + high[i] * 0.5
	return _wav(_seamless(_normalised(data, 0.8), length), true)


## A loop of tyres rolling on the road: a low, dull roar, with a faint hiss of the tread.
static func roll_loop() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var length := MIX_RATE * 2
	var noise := _noise(rng, length + LOOP_FADE)
	var roar := _band_pass(noise, 140.0, 0.7)
	var body := _band_pass(noise, 420.0, 1.0)
	var hiss := _band_pass(noise, 2200.0, 0.8)
	var data := PackedFloat32Array()
	data.resize(noise.size())
	for i in noise.size():
		data[i] = roar[i] + body[i] * 0.45 + hiss[i] * 0.06
	return _wav(_seamless(_normalised(data, 0.8), length), true)


## A relay's click at [param pitch] hertz lasting [param length] seconds.
static func click(pitch: float, length: float) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pitch)
	var samples := roundi(length * MIX_RATE)
	var data := PackedFloat32Array()
	data.resize(samples)
	for i in samples:
		var t := float(i) / MIX_RATE
		var fade := exp(-t / length * 6.0)
		data[i] = (sin(TAU * pitch * t) * 0.6 + rng.randf_range(-1.0, 1.0) * 0.4) * fade
	return _wav(data, false)


## A tyre's thump against a kerb: a low knock dying away.
static func knock() -> AudioStreamWAV:
	var samples := roundi(0.18 * MIX_RATE)
	var data := PackedFloat32Array()
	data.resize(samples)
	for i in samples:
		var t := float(i) / MIX_RATE
		data[i] = sin(TAU * (70.0 + 60.0 * exp(-t * 30.0)) * t) * exp(-t * 22.0)
	return _wav(data, false)


## Samples crossfaded over at the end of a noise loop, so it joins up with no click.
const LOOP_FADE := 2048


## [param count] samples of white noise.
static func _noise(rng: RandomNumberGenerator, count: int) -> PackedFloat32Array:
	var data := PackedFloat32Array()
	data.resize(count)
	for i in count:
		data[i] = rng.randf_range(-1.0, 1.0)
	return data


## Noise wandering smoothly between -1 and 1 about [param rate] times a second.
static func _smooth_noise(rng: RandomNumberGenerator, count: int, rate: float) -> PackedFloat32Array:
	var data := PackedFloat32Array()
	data.resize(count)
	var step := maxi(roundi(MIX_RATE / rate), 1)
	var from := rng.randf_range(-1.0, 1.0)
	var to := rng.randf_range(-1.0, 1.0)
	for i in count:
		var phase := float(i % step) / step
		if i > 0 and i % step == 0:
			from = to
			to = rng.randf_range(-1.0, 1.0)
		data[i] = lerpf(from, to, smoothstep(0.0, 1.0, phase))
	return data


## [param data] through a band-pass filter at [param centre] hertz of sharpness [param q]: the
## two-pole filter of the Audio EQ Cookbook, unit gain at the centre.
static func _band_pass(data: PackedFloat32Array, centre: float, q: float) -> PackedFloat32Array:
	var w := TAU * centre / MIX_RATE
	var alpha := sin(w) / (2.0 * q)
	var a0 := 1.0 + alpha
	var b0 := alpha / a0
	var a1 := -2.0 * cos(w) / a0
	var a2 := (1.0 - alpha) / a0
	var out := PackedFloat32Array()
	out.resize(data.size())
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	for i in data.size():
		var y := b0 * (data[i] - x2) - a1 * y1 - a2 * y2
		x2 = x1
		x1 = data[i]
		y2 = y1
		y1 = y
		out[i] = y
	return out


## [param data] scaled so its loudest sample is [param peak].
static func _normalised(data: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var top := 0.0
	for v in data:
		top = maxf(top, absf(v))
	if top > 0.0:
		for i in data.size():
			data[i] *= peak / top
	return data


## The first [param length] samples of [param data], its tail past them crossfaded into its head,
## so the loop flows from its last sample back to its first as the sound would have gone on.
static func _seamless(data: PackedFloat32Array, length: int) -> PackedFloat32Array:
	var fade := data.size() - length
	var out := data.slice(0, length)
	for i in fade:
		var a := float(i) / fade
		out[i] = data[i] * sqrt(a) + data[length + i] * sqrt(1.0 - a)
	return out


static func _wav(data: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, clampi(roundi(data[i] * 30000.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = data.size()
	return wav


## The sound [param key], made by [param make] the first time any car asks for it: what the code
## makes never changes, so every car and every restart shares it.
static func _made(key: StringName, make: Callable) -> AudioStream:
	if not _cache.has(key):
		_cache[key] = make.call()
	return _cache[key]


## The recording at [param path], or what [param make] makes when it is missing.
static func _recording(path: String, make: Callable) -> AudioStream:
	if ResourceLoader.exists(path):
		return load(path)
	return make.call()


func _player(p_name: String, stream: AudioStream) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = p_name
	player.stream = stream
	player.bus = BUS
	player.unit_size = 4.0
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	add_child(player)
	return player


## The car's audio bus, made when the project's layout does not have one.
static func _ensure_bus() -> void:
	if AudioServer.get_bus_index(BUS) != -1:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, BUS)
	AudioServer.set_bus_send(index, &"Master")
