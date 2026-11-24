extends Node3D
## Shows a 2D user interface on a flat panel in the 3D world.
##
## The UI lives inside the SubViewport child and its image is drawn on a quad of
## [member panel_size] metres, always on top of the world so a car's cabin never hides it.
## VR pointers (vr_pointer.gd) find panels through the [constant GROUP] group by geometry, not
## physics, so a panel also works while the game is paused, and their hits arrive here as regular
## mouse events: any Control UI works unchanged.

const GROUP := &"vr_ui_panel"

## Size of the panel in metres; the SubViewport keeps its pixel size.
@export var panel_size := Vector2(1.6, 0.9)

var _last_position := Vector2.ZERO
var _pressed := false

@onready var _viewport: SubViewport = $SubViewport
@onready var _mesh: MeshInstance3D = $Mesh


func _ready() -> void:
	add_to_group(GROUP)
	_viewport.transparent_bg = true
	_viewport.gui_embed_subwindows = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS

	var quad := QuadMesh.new()
	quad.size = panel_size
	_mesh.mesh = quad

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	material.no_depth_test = true
	material.render_priority = 10
	material.albedo_texture = _viewport.get_texture()
	_mesh.material_override = material


## Puts a Control (such as a menu) inside the panel.
func set_content(content: Control) -> void:
	_viewport.add_child(content)


## Distance along a ray to the panel's face, or a negative number when the ray misses it.
func ray_distance(from: Vector3, direction: Vector3) -> float:
	var face := _mesh.global_transform
	var normal := face.basis.z.normalized()
	var facing := normal.dot(direction)
	if absf(facing) < 0.0001:
		return -1.0
	var distance := normal.dot(face.origin - from) / facing
	if distance <= 0.0:
		return -1.0
	var local := face.affine_inverse() * (from + direction * distance)
	if absf(local.x) > panel_size.x * 0.5 or absf(local.y) > panel_size.y * 0.5:
		return -1.0
	return distance


## Called by a pointer every frame while it points at the panel.
func pointer_move(global_point: Vector3) -> void:
	var position_2d := _to_viewport(global_point)
	var event := InputEventMouseMotion.new()
	event.position = position_2d
	event.global_position = position_2d
	event.relative = position_2d - _last_position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if _pressed else 0
	_last_position = position_2d
	_viewport.push_input(event)


## Called by a pointer when its trigger is pressed or released over the panel.
func pointer_button(global_point: Vector3, pressed: bool) -> void:
	_last_position = _to_viewport(global_point)
	_send_button(pressed)


## Called by a pointer when it stops pointing at the panel.
func pointer_exit() -> void:
	if _pressed:
		_send_button(false)
	# Moves the virtual mouse away so buttons lose their hover state.
	var event := InputEventMouseMotion.new()
	event.position = Vector2(-1000, -1000)
	event.global_position = event.position
	_last_position = event.position
	_viewport.push_input(event)


func _send_button(pressed: bool) -> void:
	_pressed = pressed
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.position = _last_position
	event.global_position = _last_position
	event.button_mask = MOUSE_BUTTON_MASK_LEFT if pressed else 0
	_viewport.push_input(event)


func _to_viewport(global_point: Vector3) -> Vector2:
	var local := _mesh.global_transform.affine_inverse() * global_point
	var uv := Vector2(local.x / panel_size.x + 0.5, 0.5 - local.y / panel_size.y)
	return uv * Vector2(_viewport.size)
