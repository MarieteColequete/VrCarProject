extends SceneTree
## Cuts the car's recordings ([CarSound]) from the Freesound previews in each
## assets/freesound/*/source/ folder, once: mono, 44.1 kHz, 16-bit WAV. Each loop is a steady
## stretch whose next half second is crossfaded into its head, so it runs on from its end into its
## start, and is brought to a set loudness, so the levels in [CarSound] mean the same for each.
## Run from the project folder:
## godot --headless --path . -s res://tools/car_recordings.gd

const SET := "res://assets/freesound/"
const RATE := 44100
const FADE := RATE / 2


func _init() -> void:
	var road := _decode("road_interior/source/237374__squareal__car-driving-interior.ogg")
	_save(_loudness(_loop(road, 12.0, 28.0), -14.0), "road_interior/road_interior.wav")
	var asphalt := _decode("tyres_asphalt/source/591079__orlandorizo__car-rolling-on-asphalt.ogg")
	_save(_loudness(_loop(asphalt, 62.0, 75.0), -14.0), "tyres_asphalt/tyres_asphalt.wav")
	var dirt := _decode("road_dirt/source/637192__kyles__auto-truck-int-driving-on-dirt-road.ogg")
	_save(_loudness(_loop(dirt, 5.0, 25.0), -14.0), "road_dirt/road_dirt.wav")
	var gravel := _decode("tyres_gravel/source/577504__trp__car-tire-on-gravel-rear-cu.ogg")
	_save(_loudness(_loop(gravel, 22.0, 40.0), -14.0), "tyres_gravel/tyres_gravel.wav")
	var slide := _decode(
		"slide_gravel/source/529225__unplugthefridge__car-tires-start-and-stop-on-gravel-shoulder.ogg")
	_save(_loudness(_loop(slide, 4.5, 9.5), -14.0), "slide_gravel/slide_gravel.wav")
	var idle := _decode("engine_idle/source/369053__andrewalexander__car-idle-loop.ogg")
	_save(_loudness(_loop(idle, 0.5, 14.0), -16.0), "engine_idle/engine_idle.wav")
	# The relay clicks every 0.35 s, on and off; the louder clicks at 0.01, 0.17 and 3.01 s are
	# the stalk.
	var signal_ := _decode("indicator/source/446322__mpierluissi__nissan-sentra-turning-signal.ogg")
	var on := _clip(signal_, 0.43, 0.10)
	var off := _clip(signal_, 0.78, 0.10)
	var peak := maxf(_peak(on), _peak(off))
	_save(_gain(on, linear_to_db(0.8 / peak)), "indicator/indicator_on.wav")
	_save(_gain(off, linear_to_db(0.8 / peak)), "indicator/indicator_off.wav")
	quit()


## The file at [param path] in [constant SET], decoded to mono samples at [constant RATE].
func _decode(path: String) -> PackedFloat32Array:
	var stream := AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(SET + path))
	var playback := stream.instantiate_playback()
	playback.start(0.0)
	var out := PackedFloat32Array()
	while playback.is_playing():
		var chunk := playback.mix_audio(1.0, 8192)
		if chunk.is_empty():
			break
		for frame in chunk:
			out.append((frame.x + frame.y) * 0.5)
	return out


## Seconds [param from] to [param to] of [param data] as a loop: the [constant FADE] samples after
## [param to] crossfaded into its head, equal power.
func _loop(data: PackedFloat32Array, from: float, to: float) -> PackedFloat32Array:
	var a := int(from * RATE)
	var b := int(to * RATE)
	var out := data.slice(a, b)
	for i in FADE:
		var t := float(i) / FADE
		out[i] = data[a + i] * sqrt(t) + data[b + i] * sqrt(1.0 - t)
	return out


## [param length] seconds of [param data] from [param from], its last 20 ms faded out.
func _clip(data: PackedFloat32Array, from: float, length: float) -> PackedFloat32Array:
	var out := data.slice(int(from * RATE), int((from + length) * RATE))
	var tail := int(0.02 * RATE)
	for i in tail:
		out[out.size() - tail + i] *= 1.0 - float(i) / tail
	return out


func _loudness(data: PackedFloat32Array, rms_db: float) -> PackedFloat32Array:
	var sum := 0.0
	for v in data:
		sum += v * v
	return _gain(data, rms_db - linear_to_db(sqrt(sum / data.size())))


func _peak(data: PackedFloat32Array) -> float:
	var top := 0.0
	for v in data:
		top = maxf(top, absf(v))
	return top


func _gain(data: PackedFloat32Array, db: float) -> PackedFloat32Array:
	var g := db_to_linear(db)
	for i in data.size():
		data[i] = clampf(data[i] * g, -1.0, 1.0)
	return data


func _save(data: PackedFloat32Array, path: String) -> void:
	var bytes := PackedByteArray()
	bytes.resize(data.size() * 2)
	for i in data.size():
		bytes.encode_s16(i * 2, clampi(roundi(data[i] * 32767.0), -32768, 32767))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	wav.save_to_wav(ProjectSettings.globalize_path(SET + path))
	print("made %s, %.2f s" % [path, wav.get_length()])
