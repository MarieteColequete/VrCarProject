extends Node
## Autoload "PauseMenu".
##
## Pauses any scene that is not a menu: the scene tree stops, so the car, the traffic and the
## exam clock freeze, and a menu offers Resume, Options and Main menu. Scenes need nothing of
## their own; a scene opts out by putting its root in the [code]no_pause[/code] group, as the main
## menu does. The [code]menu[/code] input action opens and closes it (Esc, gamepad Start, and the
## left VR controller's menu button, which [DriverView] turns into the action while driving and
## [VRControllerInput] while the tree is paused). It stays closed while another overlay, such as
## the drive scene's briefing or result, is up.

const PAUSE_ACTION := &"menu"
const NO_PAUSE_GROUP := &"no_pause"
const PAUSE_UI := preload("res://ui/menus/pause_menu_ui.tscn")

## True while the game is paused by this menu.
var is_open := false

var _overlay: MenuOverlay
var _ui  # pause_menu_ui.gd
var _mouse_mode_before := Input.MOUSE_MODE_VISIBLE


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Whether the current scene can be paused now.
func can_pause() -> bool:
	var scene := get_tree().current_scene
	return (not is_open and scene != null and not scene.is_in_group(NO_PAUSE_GROUP)
			and MenuOverlay.open_count == 0)


func open(focus_first := false) -> void:
	if not can_pause():
		return
	is_open = true
	get_tree().paused = true
	_mouse_mode_before = Input.mouse_mode
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_ui = PAUSE_UI.instantiate()
	_ui.resume_requested.connect(resume)
	_ui.main_menu_requested.connect(_on_main_menu_requested)
	_overlay = MenuOverlay.new()
	add_child(_overlay)
	_overlay.present(_ui)
	if focus_first:
		_ui.using_pointer = false
		_ui.focus_default.call_deferred()


func resume() -> void:
	if not is_open:
		return
	_close()
	get_tree().paused = false
	Input.mouse_mode = _mouse_mode_before


## Closes the options if they are open, otherwise resumes.
func back() -> void:
	if _ui and _ui.back():
		return
	resume()


func _on_main_menu_requested() -> void:
	_close()
	GameFlow.to_main_menu(get_tree())


func _close() -> void:
	is_open = false
	Settings.save_settings()
	if _overlay:
		_overlay.queue_free()
	_overlay = null
	_ui = null


## Read before the scene sees it, so pausing takes Esc over from the scene's own use of it
## (DriverView frees the mouse on Esc), the mouse state recorded for resuming is the scene's, and
## the debug HUD's own menu hook ([signal DebugHud.menu_requested]) is left for scenes with no
## pause menu.
func _input(event: InputEvent) -> void:
	if is_open:
		if event.is_action_pressed(PAUSE_ACTION) or event.is_action_pressed(&"ui_cancel"):
			get_viewport().set_input_as_handled()
			back()
	elif event.is_action_pressed(PAUSE_ACTION) and can_pause():
		get_viewport().set_input_as_handled()
		# On a monitor, focus Resume so a keyboard or gamepad can use the menu right away; in VR
		# the laser pointer is used instead.
		open(not XRManager.is_vr)
