extends Node
## Autoload "XRManager".
##
## Tries to start OpenXR when the game launches. With a headset the game runs in VR mode, and in
## the menus the monitor shows one eye of the headset, which Godot mirrors to the window on PC;
## while driving, [DriverView] shows the instructor's view there instead.
## Without one it silently falls back to desktop mode (screen with mouse and keyboard, or gamepad).
## Other scripts only need to check [member is_vr] to decide what to show.
## [code]--xr-mode off[/code] on the command line forces desktop mode even with a headset.

## Emitted when the player recentres the view from the headset's system menu.
signal recentered

## True when the game is rendering to a VR headset.
var is_vr := false

var _interface: OpenXRInterface


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_interface = XRServer.find_interface("OpenXR") as OpenXRInterface
	if _interface and _interface.is_initialized():
		is_vr = true
		# The headset paces the frames; V-Sync on the monitor would only slow it down.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().use_xr = true
		_interface.instance_exiting.connect(_on_instance_exiting)
		_interface.pose_recentered.connect(_on_pose_recentered)
		# DriverView feeds the controllers to the car; this closes the pause menu while paused.
		add_child(VRControllerInput.new())
		print("XRManager: OpenXR started, running in VR mode.")
	else:
		print("XRManager: no VR headset found, running in desktop mode.")


func _on_instance_exiting() -> void:
	# The player closed the game from the headset's menu; OpenXR expects the process to end.
	get_tree().quit()


func _on_pose_recentered() -> void:
	XRServer.center_on_hmd(XRServer.RESET_BUT_KEEP_TILT, true)
	recentered.emit()
