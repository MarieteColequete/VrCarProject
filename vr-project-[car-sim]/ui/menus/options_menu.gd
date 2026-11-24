extends PanelContainer
## Options panel: audio volumes, 3D quality, and (on a monitor only) display settings.
## Changes apply immediately and are saved when the panel is closed.

signal closed

const DISPLAY_MODES: PackedStringArray = ["Windowed", "Fullscreen"]

var _resolutions: Array[Vector2i] = []

@onready var _sliders: Dictionary = {
	&"Master": %MasterSlider,
	&"Music": %MusicSlider,
	&"SFX": %SfxSlider,
}
@onready var _value_labels: Dictionary = {
	&"Master": %MasterValue,
	&"Music": %MusicValue,
	&"SFX": %SfxValue,
}
# Untyped on purpose: they use ui/components/option_stepper.gd.
@onready var _display_stepper = %DisplayStepper
@onready var _resolution_stepper = %ResolutionStepper
@onready var _scale_stepper = %ScaleStepper
@onready var _msaa_stepper = %MsaaStepper
@onready var _vsync_check: CheckBox = %VSyncCheck


func _ready() -> void:
	for bus in _sliders:
		var slider: HSlider = _sliders[bus]
		slider.value_changed.connect(_on_volume_changed.bind(bus))

	var scale_names := PackedStringArray()
	for value in Settings.RENDER_SCALES:
		scale_names.append("%d%%" % roundi(value * 100.0))
	_scale_stepper.set_items(scale_names)
	_msaa_stepper.set_items(Settings.MSAA_NAMES)
	_display_stepper.set_items(DISPLAY_MODES)

	_display_stepper.item_selected.connect(_on_display_selected)
	_resolution_stepper.item_selected.connect(_on_resolution_selected)
	_scale_stepper.item_selected.connect(_on_scale_selected)
	_msaa_stepper.item_selected.connect(Settings.set_msaa)
	_vsync_check.toggled.connect(Settings.set_vsync)
	%BackButton.pressed.connect(close)
	%DefaultsButton.pressed.connect(_on_defaults_pressed)

	# In VR the headset owns the display: only the quality rows of the video column stay.
	var show_display: bool = Settings.display_settings_available()
	for row: Control in [%DisplayRow, %ResolutionRow, %VSyncRow]:
		row.visible = show_display
	%VRNote.visible = not show_display
	_setup_focus_chain(show_display)
	refresh()


func open() -> void:
	refresh()
	show()


func close() -> void:
	Settings.save_settings()
	hide()
	closed.emit()


## Puts keyboard and gamepad focus on the first option.
func focus_first() -> void:
	%MasterSlider.grab_focus()


## Updates every control from the current Settings without triggering changes.
func refresh() -> void:
	for bus in _sliders:
		var value: float = Settings.get_volume(bus) * 100.0
		(_sliders[bus] as HSlider).set_value_no_signal(value)
		_update_volume_label(bus, value)

	_display_stepper.select(1 if Settings.fullscreen else 0)

	_resolutions = Settings.get_available_resolutions()
	var names := PackedStringArray()
	for res in _resolutions:
		names.append("%d x %d" % [res.x, res.y])
	_resolution_stepper.set_items(names, maxi(_resolutions.find(Settings.resolution), 0))
	_resolution_stepper.set_disabled(Settings.fullscreen)

	_scale_stepper.select(_closest_scale_index(Settings.render_scale))
	_msaa_stepper.select(Settings.msaa)
	_vsync_check.set_pressed_no_signal(Settings.vsync)


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _on_volume_changed(value: float, bus: StringName) -> void:
	Settings.set_volume(bus, value / 100.0)
	_update_volume_label(bus, value)


func _update_volume_label(bus: StringName, value: float) -> void:
	(_value_labels[bus] as Label).text = "%d%%" % roundi(value)


func _on_display_selected(index: int) -> void:
	Settings.set_fullscreen(index == 1)
	_resolution_stepper.set_disabled(Settings.fullscreen)


func _on_resolution_selected(index: int) -> void:
	Settings.set_resolution(_resolutions[index])


func _on_scale_selected(index: int) -> void:
	Settings.set_render_scale(Settings.RENDER_SCALES[index])


func _on_defaults_pressed() -> void:
	Settings.reset_to_defaults()
	refresh()


## Sliders and steppers use left and right to change their value, so up and down (and Tab) walk
## through every option in one list, top to bottom, then the buttons.
func _setup_focus_chain(include_display: bool) -> void:
	var chain: Array[Control] = [%MasterSlider, %MusicSlider, %SfxSlider]
	if include_display:
		chain.append_array([_display_stepper, _resolution_stepper, _vsync_check])
	chain.append_array([_scale_stepper, _msaa_stepper, %DefaultsButton, %BackButton])
	for i in chain.size():
		var control := chain[i]
		var previous := control.get_path_to(chain[i - 1])
		var next := control.get_path_to(chain[(i + 1) % chain.size()])
		control.focus_neighbor_top = previous
		control.focus_previous = previous
		control.focus_neighbor_bottom = next
		control.focus_next = next


func _closest_scale_index(value: float) -> int:
	var best := 0
	for i in Settings.RENDER_SCALES.size():
		if absf(Settings.RENDER_SCALES[i] - value) < absf(Settings.RENDER_SCALES[best] - value):
			best = i
	return best
