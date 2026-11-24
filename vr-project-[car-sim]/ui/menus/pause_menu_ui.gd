extends MenuScreen
## The pause menu interface: Resume, Options and Main menu. The PauseMenu autoload shows it and
## decides what resuming and leaving do.

signal resume_requested
signal main_menu_requested

const DESKTOP_HINT := "Esc / Start: resume"
const VR_HINT := "Menu button: resume  ·  Trigger: choose"

@onready var _pause_page: Control = %PausePage
@onready var _options = %OptionsMenu


func _ready() -> void:
	super()
	%ResumeButton.pressed.connect(resume_requested.emit)
	%OptionsButton.pressed.connect(open_options)
	%MainMenuButton.pressed.connect(main_menu_requested.emit)
	_options.closed.connect(_on_options_closed)
	_options.hide()
	%Hint.text = VR_HINT if XRManager.is_vr else DESKTOP_HINT


func default_focus() -> Control:
	return %ResumeButton


func focus_default() -> void:
	if _options.visible:
		_options.focus_first()
	else:
		super()


func open_options() -> void:
	_pause_page.hide()
	_options.open()
	if not using_pointer:
		_options.focus_first()


## Steps back one page: closes the options if they are open. Returns false when already on the
## first page, where going back means resuming.
func back() -> bool:
	if _options.visible:
		_options.close()
		return true
	return false


func _on_options_closed() -> void:
	_pause_page.show()
	focus_for_keyboard(%OptionsButton)
