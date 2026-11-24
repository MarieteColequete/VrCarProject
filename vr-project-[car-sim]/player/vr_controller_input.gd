class_name VRControllerInput
extends Node
## Closes the pause menu from a VR controller. While driving, [DriverView] turns the motion
## controllers into the input actions, the left menu button into [code]menu[/code] among them, but
## it stops with the scene tree when the game pauses. So while the tree is paused, this node sends
## [code]menu[/code] for a press of either controller's menu button, and the button that opened
## the pause menu also closes it. The menus themselves are used with the laser pointers.
## [XRManager] adds this node when the game runs in VR; it keeps running while the tree is paused.

const ACTION := &"menu"
const HANDS: Array[StringName] = [&"left_hand", &"right_hand"]
const BUTTON := &"menu_button"

var _was_pressed := false
var _was_paused := false


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _process(_delta: float) -> void:
	var pressed := HANDS.any(func(hand: StringName) -> bool: return _read_tracker(hand) == true)
	var paused := get_tree().paused
	if sends_menu(pressed, _was_pressed, paused, _was_paused):
		var event := InputEventAction.new()
		event.action = ACTION
		event.pressed = true
		Input.parse_input_event(event)
	_was_pressed = pressed
	_was_paused = paused


## Whether a frame sends [code]menu[/code]: a new press of the menu button while the tree is paused
## and was already paused the frame before, so the press that opened the pause menu (seen by
## [DriverView] while the tree still ran) does not close it again at once.
static func sends_menu(pressed: bool, was_pressed: bool, paused: bool, was_paused: bool) -> bool:
	return pressed and not was_pressed and paused and was_paused


static func _read_tracker(hand: StringName) -> Variant:
	var tracker := XRServer.get_tracker(hand) as XRPositionalTracker
	return tracker.get_input(BUTTON) if tracker else null
