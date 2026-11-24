extends TestCase
## The VR menu button while the game is paused: when it sends the menu action that closes the pause
## menu.


func run() -> void:
	expect(InputMap.has_action(VRControllerInput.ACTION), "the menu action exists")
	expect(VRControllerInput.sends_menu(true, false, true, true),
		"a new press of the menu button while paused sends menu")
	expect(not VRControllerInput.sends_menu(true, true, true, true),
		"a menu button held down sends menu once, not every frame")
	expect(not VRControllerInput.sends_menu(true, false, false, false),
		"while driving the menu button is left to the driver's view")
	expect(not VRControllerInput.sends_menu(true, false, true, false),
		"the press that paused the game does not close the pause menu at once")
	expect(not VRControllerInput.sends_menu(false, false, true, true),
		"no press sends nothing")
