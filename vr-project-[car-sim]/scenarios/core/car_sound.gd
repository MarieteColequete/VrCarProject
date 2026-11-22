class_name CarSound
extends Node3D
## The car's sounds, heard in the cabin: the engine, the indicator's tick, the tyres squealing near
## their grip, and a thump when a tyre meets a kerb. Every sound is made here when the car is built,
## so the game carries no recordings: the engine is a four-cylinder's firing pulses and their
## harmonics, recorded once slow and once fast and crossfaded and pitched with the revolutions,
## louder on the throttle. They play on the [constant BUS] audio bus. Nothing here takes part in the
## simulation.

const BUS := &"Car"
const MIX_RATE := 22050
## The revolutions the engine's two loops are made at.
const LOW_RPM := 1000.0
const HIGH_RPM := 4000.0
## The engine's loudness, decibels, off the throttle and on it, and while a gear changes.
const ENGINE_COAST_DB := -14.0
const ENGINE_FULL_DB := -4.0
const SHIFT_DIP_DB := -6.0
## How hard the tyres work when they begin to squeal, and when at full voice, as a share of
## their peak grip ([method TyreModel.usage]); and the speed below which they never do.
const SQUEAL_FROM := 0.7
const SQUEAL_FULL := 1.3
const SQUEAL_SPEED := 4.0

var engine_low: AudioStreamPlayer3D
var engine_high: AudioStreamPlayer3D
var squeal: AudioStreamPlayer3D
var tick: AudioStreamPlayer3D
var thump: AudioStreamPlayer3D

## How many times the indicator has ticked, on and off.
var ticks := 0

var _tick_on: AudioStreamWAV
var _tick_off: AudioStreamWAV
var _lit := false


func _init() -> void:
	name = "Sound"
	_ensure_bus()
	engine_low = _player("EngineLow", engine_loop(LOW_RPM, 11))
	engine_high = _player("EngineHigh", engine_loop(HIGH_RPM, 23))
	squeal = _player("Squeal", squeal_loop())
	_tick_on = click(2600.0, 0.012)
	_tick_off = click(1700.0, 0.010)
	tick = _player("Tick", _tick_on)
	thump = _player("Thump", knock())
	# The indicator relay sits behind the dashboard, the engine ahead of it.
	engine_low.position = Vector3(0.0, 0.6, -1.6)
	engine_high.position = engine_low.position
	tick.position = Vector3(-0.3, 0.9, -0.5)


func _ready() -> void:
	for player: AudioStreamPlayer3D in [engine_low, engine_high, squeal]:
		player.play()
	squeal.volume_db = -80.0


## Follows the car for a step: the engine at [param rpm] with [param throttle] (0 to 1), dipped
## while [param shifting]; the indicator ticking as [param blink_lit] turns on and off; the tyres
## working [param work] (1 at their peak grip) at [param speed] metres per second.
func follow(rpm: float, throttle: float, shifting: bool, blink_lit: bool, work: float,
		speed: float) -> void:
	var mix := engine_mix(rpm, throttle)
	var dip := SHIFT_DIP_DB if shifting else 0.0
	engine_low.volume_db = mix.low_db + dip
	engine_high.volume_db = mix.high_db + dip
	engine_low.pitch_scale = mix.low_pitch
	engine_high.pitch_scale = mix.high_pitch
	squeal.volume_db = squeal_db(work, speed)
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


## How loud the tyres squeal, decibels, working [param work] at [param speed]: silent below
## [constant SQUEAL_FROM] or [constant SQUEAL_SPEED], loudest from [constant SQUEAL_FULL].
static func squeal_db(work: float, speed: float) -> float:
	if absf(speed) < SQUEAL_SPEED:
		return -80.0
	var over := (absf(work) - SQUEAL_FROM) / (SQUEAL_FULL - SQUEAL_FROM)
	if over <= 0.0:
		return -80.0
	return lerpf(-24.0, -8.0, clampf(over, 0.0, 1.0))


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


## A loop of tyres squealing: a wavering whine over hiss.
static func squeal_loop() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var samples := MIX_RATE
	var data := PackedFloat32Array()
	data.resize(samples)
	var hiss := 0.0
	for i in samples:
		var t := float(i) / MIX_RATE
		# Whole cycles over the loop, so it joins up: 900 Hz wavering 6 times a second.
		var whine := sin(TAU * 900.0 * t + 0.6 * sin(TAU * 6.0 * t))
		hiss = lerpf(hiss, rng.randf_range(-1.0, 1.0), 0.5)
		data[i] = whine * 0.5 + hiss * 0.25
	return _wav(data, true)


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
