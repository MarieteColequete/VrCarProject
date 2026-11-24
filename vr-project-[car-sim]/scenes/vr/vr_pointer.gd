extends XRController3D
## Laser pointer for a VR controller.
##
## Points at the UI panels in the [code]vr_ui_panel[/code] group (ui_panel_3d.gd) and clicks them
## with the trigger. Only the active pointer interacts; pulling the trigger on the other hand makes
## that one active instead. It runs on the frame, not the physics tick, so it also works while the
## game is paused when its process mode allows it. Button names come from Godot's default OpenXR
## action map.

signal activated(pointer: XRController3D)

const PANEL_GROUP := &"vr_ui_panel"

@export var max_distance := 5.0
@export var click_action := &"trigger_click"

## The active pointer shows a full laser and sends hover and click events.
var is_active_pointer := false:
	set(value):
		is_active_pointer = value
		if not value:
			_set_target(null)

var _target: Node3D = null
var _hit_point := Vector3.ZERO
var _trigger_down := false

@onready var _laser: MeshInstance3D = $Laser
@onready var _dot: MeshInstance3D = $Dot


## Makes the first pointer active and keeps exactly one of them active from then on.
static func link(pointers: Array) -> void:
	for pointer in pointers:
		pointer.is_active_pointer = pointer == pointers[0]
		pointer.activated.connect(func(chosen: XRController3D) -> void:
			for other in pointers:
				if other != chosen and is_instance_valid(other):
					other.is_active_pointer = false)


func _ready() -> void:
	button_pressed.connect(_on_button_pressed)
	button_released.connect(_on_button_released)


func _process(_delta: float) -> void:
	if not get_has_tracking_data():
		_set_target(null)
		_laser.visible = false
		_dot.visible = false
		return

	var origin := global_position
	var direction := -global_basis.z
	var nearest: Node3D = null
	var nearest_distance := max_distance
	for panel: Node3D in get_tree().get_nodes_in_group(PANEL_GROUP):
		if not panel.is_visible_in_tree():
			continue
		var distance: float = panel.ray_distance(origin, direction)
		if distance > 0.0 and distance < nearest_distance:
			nearest = panel
			nearest_distance = distance
	if nearest:
		_hit_point = origin + direction * nearest_distance
	if is_active_pointer:
		_set_target(nearest)
		if _target:
			_target.pointer_move(_hit_point)

	_update_visuals(nearest_distance if nearest else -1.0)


func _set_target(new_target: Node3D) -> void:
	if new_target == _target:
		return
	if _target and is_instance_valid(_target):
		_target.pointer_exit()
	_target = new_target


func _on_button_pressed(action_name: String) -> void:
	if action_name != click_action:
		return
	_trigger_down = true
	if not is_active_pointer:
		is_active_pointer = true
		activated.emit(self)
		return  # The first pull only switches hands.
	if _target:
		_target.pointer_button(_hit_point, true)
		trigger_haptic_pulse(&"haptic", 0.0, 0.3, 0.05, 0.0)


func _on_button_released(action_name: String) -> void:
	if action_name != click_action or not _trigger_down:
		return
	_trigger_down = false
	if _target:
		_target.pointer_button(_hit_point, false)


## A negative hit_distance means no panel is being pointed at.
func _update_visuals(hit_distance: float) -> void:
	var length: float
	if is_active_pointer:
		length = hit_distance if hit_distance > 0.0 else max_distance * 0.4
	else:
		length = 0.12  # A small stub on the inactive hand.
	_laser.visible = true
	_laser.scale = Vector3(1.0, 1.0, length)
	_laser.position = Vector3(0.0, 0.0, -length * 0.5)
	_dot.visible = is_active_pointer and hit_distance > 0.0
	_dot.position = Vector3(0.0, 0.0, -(hit_distance - 0.005))
