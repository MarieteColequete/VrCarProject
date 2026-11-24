extends Node
## Autoload "Settings".
##
## Stores the player's options, applies them and saves them to [code]user://settings.cfg[/code]
## so they survive restarts. Everything applies game wide, so every scene gets it without any
## setup of its own:
## - Volumes are set on the audio buses (default_bus_layout.tres); a sound plays at the chosen
##   volume as long as it uses the Master, Music, or SFX bus.
## - Quality (3D resolution and anti-aliasing) is set on the root viewport, which stays the same
##   across scene changes and is also what the headset renders through.
## - Display settings (window mode, resolution, V-Sync) apply on a monitor only; in VR the
##   headset controls the display.

const SAVE_PATH := "user://settings.cfg"

## Audio buses that get a volume slider.
const AUDIO_BUSES: Array[StringName] = [&"Master", &"Music", &"SFX"]

## Window sizes offered in the options menu (only the ones that fit the screen are shown).
const RESOLUTIONS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440),
	Vector2i(3840, 2160),
]

## 3D render scale steps (1.0 is native resolution, lower is faster).
const RENDER_SCALES: Array[float] = [0.5, 0.67, 0.75, 0.85, 1.0]

## Anti-aliasing steps, as multisample levels of the root viewport.
const MSAA_LEVELS: Array[Viewport.MSAA] = [
	Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X,
]
const MSAA_NAMES: PackedStringArray = ["Off", "2x", "4x"]

const DEFAULT_VOLUME := 0.8

## Linear volume (0 to 1) for each bus in AUDIO_BUSES.
var volumes: Dictionary = {}
var fullscreen := false
var resolution := Vector2i(1280, 720)
var vsync := true
var render_scale := 1.0
## Index into MSAA_LEVELS.
var msaa := 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	reset_to_defaults(false)
	load_settings()
	apply_all()


func reset_to_defaults(apply := true) -> void:
	for bus in AUDIO_BUSES:
		volumes[bus] = DEFAULT_VOLUME
	fullscreen = false
	resolution = RESOLUTIONS[0]
	vsync = true
	render_scale = 1.0
	msaa = 1
	if apply:
		apply_all()


func apply_all() -> void:
	for bus in AUDIO_BUSES:
		_apply_volume(bus)
	_apply_quality()
	_apply_display()


# Audio

func get_volume(bus: StringName) -> float:
	return volumes.get(bus, DEFAULT_VOLUME)


func set_volume(bus: StringName, value: float) -> void:
	volumes[bus] = clampf(value, 0.0, 1.0)
	_apply_volume(bus)


func _apply_volume(bus: StringName) -> void:
	var index := AudioServer.get_bus_index(bus)
	if index == -1:
		push_warning("Settings: audio bus '%s' does not exist." % bus)
		return
	var value: float = volumes[bus]
	AudioServer.set_bus_mute(index, value <= 0.001)
	AudioServer.set_bus_volume_db(index, linear_to_db(maxf(value, 0.001)))


# Quality

func set_render_scale(value: float) -> void:
	render_scale = clampf(value, 0.25, 2.0)
	_apply_quality()


func set_msaa(index: int) -> void:
	msaa = clampi(index, 0, MSAA_LEVELS.size() - 1)
	_apply_quality()


func _apply_quality() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var root := get_tree().root
	root.scaling_3d_scale = render_scale
	root.msaa_3d = MSAA_LEVELS[msaa]


# Display

## Display options only make sense on a monitor.
func display_settings_available() -> bool:
	return not XRManager.is_vr and DisplayServer.get_name() != "headless"


func set_fullscreen(value: bool) -> void:
	fullscreen = value
	_apply_window.call_deferred()


func set_resolution(value: Vector2i) -> void:
	resolution = value
	_apply_window.call_deferred()


func set_vsync(value: bool) -> void:
	vsync = value
	_apply_display()


## Resolutions from RESOLUTIONS that fit on the current screen.
func get_available_resolutions() -> Array[Vector2i]:
	var screen_size := DisplayServer.screen_get_size(DisplayServer.window_get_current_screen())
	var result: Array[Vector2i] = []
	for res in RESOLUTIONS:
		if res.x <= screen_size.x and res.y <= screen_size.y:
			result.append(res)
	if result.is_empty():
		result.append(RESOLUTIONS[0])
	if not result.has(resolution):
		result.append(resolution)
		result.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x * a.y < b.x * b.y)
	return result


func _apply_display() -> void:
	if not display_settings_available():
		return
	DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	_apply_window.call_deferred()


func _apply_window() -> void:
	if not display_settings_available():
		return
	var window := get_window()
	if fullscreen:
		window.mode = Window.MODE_FULLSCREEN
		return
	if window.mode != Window.MODE_WINDOWED:
		window.mode = Window.MODE_WINDOWED
	var usable := DisplayServer.screen_get_usable_rect(window.current_screen).size
	window.size = Vector2i(mini(resolution.x, usable.x), mini(resolution.y, usable.y))
	window.move_to_center()


# Saving and loading

func save_settings() -> void:
	var config := ConfigFile.new()
	for bus in AUDIO_BUSES:
		config.set_value("audio", String(bus), volumes[bus])
	config.set_value("video", "fullscreen", fullscreen)
	config.set_value("video", "resolution", resolution)
	config.set_value("video", "vsync", vsync)
	config.set_value("video", "render_scale", render_scale)
	config.set_value("video", "msaa", msaa)
	var error := config.save(SAVE_PATH)
	if error != OK:
		push_warning("Settings: could not save settings (error %d)." % error)


func load_settings() -> void:
	var config := ConfigFile.new()
	if config.load(SAVE_PATH) != OK:
		return  # First launch: keep the defaults.
	for bus in AUDIO_BUSES:
		volumes[bus] = clampf(float(config.get_value("audio", String(bus), DEFAULT_VOLUME)), 0.0, 1.0)
	fullscreen = bool(config.get_value("video", "fullscreen", fullscreen))
	var saved_resolution = config.get_value("video", "resolution", resolution)
	if saved_resolution is Vector2i:
		resolution = saved_resolution
	vsync = bool(config.get_value("video", "vsync", vsync))
	render_scale = clampf(float(config.get_value("video", "render_scale", render_scale)), 0.25, 2.0)
	msaa = clampi(int(config.get_value("video", "msaa", msaa)), 0, MSAA_LEVELS.size() - 1)
