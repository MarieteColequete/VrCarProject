class_name MenuScreen
extends Control
## Shared behaviour of the full-screen menus (main, pause, briefing and result).
##
## Keyboard and gamepad players get focus moved for them; mouse and VR laser players do not, so no
## focus ring shows up under a pointer. The first direction pressed with nothing focused focuses
## [method default_focus].

const NAV_ACTIONS: Array[StringName] = [
	&"ui_up", &"ui_down", &"ui_left", &"ui_right", &"ui_focus_next", &"ui_focus_prev",
]

## True while the player uses a mouse or a VR laser, false with a keyboard or gamepad.
var using_pointer := true


func _ready() -> void:
	if not Input.get_connected_joypads().is_empty():
		using_pointer = false


## The control focused when a keyboard or gamepad player arrives; overridden by each menu.
func default_focus() -> Control:
	return null


## Focuses the default control.
func focus_default() -> void:
	var control := default_focus()
	if control and control.is_visible_in_tree():
		control.grab_focus()


## Focuses [param control] for keyboard and gamepad players only.
func focus_for_keyboard(control: Control) -> void:
	if not using_pointer and control:
		control.grab_focus()


func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton or (event is InputEventMouseMotion and event.relative.length() > 2.0):
		using_pointer = true
	elif event is InputEventKey or event is InputEventJoypadButton:
		using_pointer = false
	elif event is InputEventJoypadMotion and absf(event.axis_value) > 0.5:
		using_pointer = false


func _unhandled_input(event: InputEvent) -> void:
	if get_viewport().gui_get_focus_owner() != null:
		return
	for action in NAV_ACTIONS:
		if event.is_action_pressed(action):
			get_viewport().set_input_as_handled()
			focus_default()
			return
