extends HBoxContainer
## A "◀ value ▶" selector.
##
## Friendlier than a drop-down in VR and with a gamepad: click the arrows, or
## focus it and press left/right. Fill it with [method set_items].

signal item_selected(index: int)

const ARROW_LEFT := preload("res://assets/ui/kenney_ui-pack/PNG/Blue/Default/arrow_basic_w.png")
const ARROW_RIGHT := preload("res://assets/ui/kenney_ui-pack/PNG/Blue/Default/arrow_basic_e.png")

## Go back to the first item after the last one (and vice versa).
@export var wrap_around := false
@export var items: PackedStringArray = []

var selected := 0
var disabled := false

var _left: Button
var _right: Button
var _value: Label


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	add_theme_constant_override(&"separation", 6)
	_left = _make_arrow(ARROW_LEFT, -1)
	_value = Label.new()
	_value.theme_type_variation = &"StepperValue"
	_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_value.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_value)
	_right = _make_arrow(ARROW_RIGHT, 1)
	focus_entered.connect(queue_redraw)
	focus_exited.connect(queue_redraw)
	_refresh()


func set_items(new_items: PackedStringArray, new_selected := 0) -> void:
	items = new_items
	select(new_selected)


## Changes the selection without emitting item_selected.
func select(index: int) -> void:
	selected = clampi(index, 0, maxi(items.size() - 1, 0))
	_refresh()


func set_disabled(value: bool) -> void:
	disabled = value
	focus_mode = Control.FOCUS_NONE if disabled else Control.FOCUS_ALL
	if disabled and has_focus():
		release_focus()
	_refresh()


func step(direction: int) -> void:
	if disabled or items.is_empty():
		return
	var index := selected + direction
	if wrap_around:
		index = wrapi(index, 0, items.size())
	index = clampi(index, 0, items.size() - 1)
	if index == selected:
		return
	selected = index
	_refresh()
	item_selected.emit(selected)


func _gui_input(event: InputEvent) -> void:
	if event.is_action_pressed(&"ui_left", true):
		step(-1)
		accept_event()
	elif event.is_action_pressed(&"ui_right", true):
		step(1)
		accept_event()


func _draw() -> void:
	if has_focus():
		draw_style_box(get_theme_stylebox(&"focus", &"Button"), Rect2(Vector2.ZERO, size))


func _make_arrow(icon: Texture2D, direction: int) -> Button:
	var button := Button.new()
	button.theme_type_variation = &"StepperArrow"
	button.icon = icon
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size = Vector2(44, 44)
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.set_meta(&"no_ui_sound", true)  # item_selected already plays a sound.
	button.pressed.connect(step.bind(direction))
	add_child(button)
	return button


func _refresh() -> void:
	if not is_node_ready():
		return
	_value.text = items[selected] if selected < items.size() else ""
	_value.modulate.a = 0.45 if disabled else 1.0
	_left.disabled = disabled or (not wrap_around and selected <= 0)
	_right.disabled = disabled or (not wrap_around and selected >= items.size() - 1)
