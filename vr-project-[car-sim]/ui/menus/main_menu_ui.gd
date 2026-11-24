extends MenuScreen
## The main menu interface: title, Play, Options and Quit, the scenario list, and the options.
##
## This Control knows nothing about VR: the main menu scene puts it on screen or on a floating
## panel. It only emits signals; the scene decides what starting a scenario and quitting do.

signal scenario_chosen(definition: ScenarioDefinition)
signal quit_requested

const DESKTOP_HINT := "Mouse  ·  Keyboard: arrows + Enter  ·  Gamepad: D-pad + A"
const VR_HINT := "Point with a controller and pull the trigger  ·  Grip: bring the menu in front of you"

var _toast_tween: Tween

@onready var _main_page: Control = %MainPage
@onready var _picker = %ScenarioPicker
@onready var _options = %OptionsMenu
@onready var _toast: Label = %Toast


func _ready() -> void:
	super()
	%PlayButton.pressed.connect(open_scenarios)
	%OptionsButton.pressed.connect(open_options)
	%QuitButton.pressed.connect(quit_requested.emit)
	_picker.scenario_chosen.connect(scenario_chosen.emit)
	_picker.closed.connect(_on_page_closed.bind(%PlayButton))
	_options.closed.connect(_on_page_closed.bind(%OptionsButton))
	_picker.hide()
	_options.hide()
	_toast.hide()
	%Hint.text = VR_HINT if XRManager.is_vr else DESKTOP_HINT

	# Small intro animation.
	_main_page.modulate.a = 0.0
	create_tween().tween_property(_main_page, "modulate:a", 1.0, 0.6).set_delay(0.15)

	if not using_pointer:
		focus_default.call_deferred()


func default_focus() -> Control:
	return %PlayButton


func focus_default() -> void:
	if _picker.visible:
		_picker.focus_first()
	elif _options.visible:
		_options.focus_first()
	else:
		super()


func open_scenarios() -> void:
	if not _picker.has_scenarios():
		show_message("No scenarios found in scenarios/catalogue.tres.")
		return
	_main_page.hide()
	_picker.open()
	if not using_pointer:
		_picker.focus_first()


func open_options() -> void:
	_main_page.hide()
	_options.open()
	if not using_pointer:
		_options.focus_first()


## Shows a short message at the bottom of the menu.
func show_message(text: String, duration := 2.5) -> void:
	_toast.text = text
	_toast.modulate.a = 0.0
	_toast.show()
	if _toast_tween:
		_toast_tween.kill()
	_toast_tween = create_tween()
	_toast_tween.tween_property(_toast, "modulate:a", 1.0, 0.2)
	_toast_tween.tween_interval(duration)
	_toast_tween.tween_property(_toast, "modulate:a", 0.0, 0.4)
	_toast_tween.tween_callback(_toast.hide)


func _on_page_closed(opener: Button) -> void:
	_main_page.show()
	focus_for_keyboard(opener)
