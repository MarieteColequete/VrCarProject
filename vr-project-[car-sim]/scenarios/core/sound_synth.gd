class_name SoundSynth
extends RefCounted
## The car's sounds made by code, where no recording is used or one is missing: an engine's loop
## at any revolutions, the tyres' squeal, skid, scrub and rolling, the indicator's click, and a
## kerb's knock. Each a seamless [AudioStreamWAV] at [constant MIX_RATE]. Static and pure; the car
## makes each once ([method CarSound._made]).

## Samples a second of every sound made.
const MIX_RATE := 22050


## A seamless loop of a four-cylinder engine at [param rpm]: a firing pulse twice a turn, each with
## its own small variation from [param noise_seed], the pulses' harmonics, and some rumble.
static func engine_loop(rpm: float, noise_seed: int) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed
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
