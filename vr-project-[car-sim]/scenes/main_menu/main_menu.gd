extends Node3D
## Main menu scene, the game's first scene.
##
## On a monitor the menu is drawn on screen over a slowly moving camera. In VR the same menu is
## shown on a floating panel and used with laser pointers. Choosing a scenario starts the drive
## scene through [GameFlow]. The scene is in the [code]no_pause[/code] group, so the pause menu
## stays closed here.

## Distance from the player's head to the menu panel in VR, in metres.
@export var vr_panel_distance := 1.8

const MENU_UI := preload("res://ui/menus/main_menu_ui.tscn")
## Seconds the menu takes to fade in from black on a monitor, as the game starts and each time it
## comes back to the menu.
const FADE_IN := 0.5
const VRPointer := preload("res://scenes/vr/vr_pointer.gd")

var _ui  # main_menu_ui.gd
var _time := 0.0

@onready var _desktop_camera: Camera3D = $DesktopCamera
@onready var _camera_start: Transform3D = _desktop_camera.transform
@onready var _xr_origin: XROrigin3D = $XROrigin3D
@onready var _xr_camera: XRCamera3D = $XROrigin3D/XRCamera3D
@onready var _ui_panel = $UIPanel3D  # ui_panel_3d.gd
@onready var _ui_layer: CanvasLayer = $UILayer


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# The sway moves the camera every drawn frame ([method _process]), so it is not interpolated
	# between physics steps.
	_desktop_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	_ui = MENU_UI.instantiate()
	_ui.scenario_chosen.connect(_on_scenario_chosen)
	_ui.quit_requested.connect(_on_quit_requested)

	if XRManager.is_vr:
		_setup_vr()
	else:
		_setup_desktop()

	if GameFlow.open_scenario_list:
		GameFlow.open_scenario_list = false
		_ui.open_scenarios()


func _setup_desktop() -> void:
	_xr_origin.queue_free()
	_ui_panel.queue_free()
	_desktop_camera.make_current()
	_ui_layer.add_child(_ui)
	_fade_in()


## Fades the menu in from the black the game starts on (the boot colour,
## [code]application/boot_splash/bg_color[/code]), over [constant FADE_IN] seconds.
func _fade_in() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 128
	var black := ColorRect.new()
	black.color = Color.BLACK
	black.mouse_filter = Control.MOUSE_FILTER_IGNORE
	black.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(black)
	add_child(layer)
	var tween := create_tween()
	tween.tween_property(black, "modulate:a", 0.0, FADE_IN)
	tween.tween_callback(layer.queue_free)


func _setup_vr() -> void:
	_desktop_camera.queue_free()
	_ui_layer.queue_free()
	_xr_camera.make_current()
	_ui_panel.set_content(_ui)

	var right = $XROrigin3D/RightController
	var left = $XROrigin3D/LeftController
	VRPointer.link([right, left])
	right.button_pressed.connect(_on_vr_button_pressed)
	left.button_pressed.connect(_on_vr_button_pressed)
	XRManager.recentered.connect(_place_panel_in_front)
	_place_after_tracking_starts()


func _place_after_tracking_starts() -> void:
	# Gives the headset a moment to start tracking, then puts the menu in front of the player.
	await get_tree().create_timer(0.6).timeout
	_place_panel_in_front()


func _process(delta: float) -> void:
	if XRManager.is_vr:
		return
	# Gentle camera sway so the background feels alive.
	_time += delta
	var offset := Vector3(sin(_time * 0.21) * 0.5, sin(_time * 0.33) * 0.12, 0.0)
	_desktop_camera.transform = _camera_start.translated(offset)


func _on_scenario_chosen(definition: ScenarioDefinition) -> void:
	Settings.save_settings()
	GameFlow.start_scenario(get_tree(), definition)


func _on_quit_requested() -> void:
	Settings.save_settings()
	get_tree().quit()


func _on_vr_button_pressed(action_name: String) -> void:
	if action_name == "grip_click":
		_place_panel_in_front()


## Moves the VR menu panel in front of the player's head, facing them.
func _place_panel_in_front() -> void:
	if not is_instance_valid(_ui_panel):
		return
	var head := _xr_camera.global_position
	if head.y < 0.3:
		head = _xr_origin.global_position + Vector3(0.0, 1.6, 0.0)  # No tracking yet.
	var forward := -_xr_camera.global_basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var target := head + forward * vr_panel_distance
	target.y = head.y - 0.15
	_ui_panel.global_position = target
	_ui_panel.look_at(Vector3(head.x, target.y, head.z), Vector3.UP, true)
