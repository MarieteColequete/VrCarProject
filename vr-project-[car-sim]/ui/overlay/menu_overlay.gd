class_name MenuOverlay
extends Node
## Shows a menu in front of the player without touching the scene it is shown over.
##
## On a monitor the menu covers the screen on a dimmed layer. In VR it goes on a panel placed in
## front of the head, with a laser pointer on each controller; both are added under the scene's
## current [XROrigin3D], so they follow a moving car, and are removed again when the overlay
## leaves the tree. The monitor mirrors the headset, so it shows the panel too.
## Free the overlay to close the menu; the menu is freed with it.

## How many overlays are open; the pause menu stays closed while another one is up.
static var open_count := 0

const PANEL_SCENE := preload("res://scenes/vr/ui_panel_3d.tscn")
const POINTER_SCENE := preload("res://scenes/vr/vr_pointer.tscn")
const VRPointer := preload("res://scenes/vr/vr_pointer.gd")

## Distance from the head to the VR panel, in metres.
@export var vr_distance := 1.3
## Size of the VR panel, in metres.
@export var vr_panel_size := Vector2(1.2, 0.675)
@export var dim_color := Color(0.05, 0.08, 0.14, 0.55)

var _presented := false
var _layer: CanvasLayer
var _panel  # ui_panel_3d.gd
var _pointers: Array = []


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


## Shows [param content] on screen or, in VR, on a panel in front of the player.
func present(content: Control) -> void:
	assert(is_inside_tree(), "Add the overlay to the tree before presenting a menu")
	_presented = true
	open_count += 1
	if XRManager.is_vr and _present_vr(content):
		return
	_present_flat(content)


func _present_flat(content: Control) -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 50
	add_child(_layer)
	var dim := ColorRect.new()
	dim.color = dim_color
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_layer.add_child(dim)
	_layer.add_child(content)


func _present_vr(content: Control) -> bool:
	var origin := _current_origin()
	if origin == null:
		return false
	_panel = PANEL_SCENE.instantiate()
	_panel.panel_size = vr_panel_size
	_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	origin.add_child(_panel)
	_panel.set_content(content)
	_place_panel(origin)
	for tracker in [&"right_hand", &"left_hand"]:
		var pointer: XRController3D = POINTER_SCENE.instantiate()
		pointer.tracker = tracker
		pointer.process_mode = Node.PROCESS_MODE_ALWAYS
		origin.add_child(pointer)
		_pointers.append(pointer)
	VRPointer.link(_pointers)
	return true


## Puts the panel at eye level in front of the head, facing it, in the origin's space. Without
## tracking the head is taken to be at the origin, which is where a car scene's DriverView puts it.
func _place_panel(origin: XROrigin3D) -> void:
	var head := XRServer.get_hmd_transform()
	var forward := -head.basis.z
	forward.y = 0.0
	forward = forward.normalized() if forward.length() > 0.01 else Vector3.FORWARD
	var target := head.origin + forward * vr_distance
	target.y = head.origin.y - 0.1
	_panel.position = target
	var eye_level := Vector3(head.origin.x, target.y, head.origin.z)
	_panel.look_at(origin.to_global(eye_level), origin.global_basis.y, true)


func _current_origin() -> XROrigin3D:
	var fallback: XROrigin3D = null
	for node in get_tree().root.find_children("*", "XROrigin3D", true, false):
		var origin := node as XROrigin3D
		if origin.current:
			return origin
		if fallback == null:
			fallback = origin
	return fallback


func _exit_tree() -> void:
	if _presented:
		_presented = false
		open_count -= 1
	for node in _pointers + [_panel]:
		if is_instance_valid(node):
			node.queue_free()
	_pointers.clear()
	_panel = null
