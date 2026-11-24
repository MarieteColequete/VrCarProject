extends PanelContainer
## Lists the scenarios of the [ScenarioCatalogue], with the details of the one under the pointer
## or focus; choosing one emits [signal scenario_chosen].

signal scenario_chosen(definition: ScenarioDefinition)
signal closed

const STAR_ON := preload("res://assets/ui/kenney_ui-pack/PNG/Yellow/Default/star.png")
const STAR_OFF := preload("res://assets/ui/kenney_ui-pack/PNG/Grey/Default/star.png")
const MAX_DIFFICULTY := 5

## The scenarios listed; the project's catalogue when empty.
@export var catalogue: ScenarioCatalogue

var _buttons: Array[Button] = []

@onready var _list: VBoxContainer = %List
@onready var _stars: HBoxContainer = %Stars


func _ready() -> void:
	if catalogue == null:
		catalogue = ScenarioCatalogue.main()
	_build_list()
	%BackButton.pressed.connect(close)


## True when the catalogue lists at least one scenario.
func has_scenarios() -> bool:
	return not _buttons.is_empty()


func open() -> void:
	show()
	if has_scenarios():
		_show_details(_buttons[0].get_meta(&"definition"))


func close() -> void:
	hide()
	closed.emit()


## Puts keyboard and gamepad focus on the first scenario.
func focus_first() -> void:
	if has_scenarios():
		_buttons[0].grab_focus()
	else:
		%BackButton.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed(&"ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _build_list() -> void:
	for definition in catalogue.scenarios:
		if definition == null:
			continue
		var button := Button.new()
		button.theme_type_variation = &"ListButton"
		button.text = definition.title
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0, 60)
		button.set_meta(&"definition", definition)
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.pressed.connect(scenario_chosen.emit.bind(definition))
		button.mouse_entered.connect(_show_details.bind(definition))
		button.focus_entered.connect(_show_details.bind(definition))
		_list.add_child(button)
		_buttons.append(button)


func _show_details(definition: ScenarioDefinition) -> void:
	%DetailTitle.text = definition.title
	%DetailCategory.text = definition.category
	%DetailTime.text = (
			"Time limit: %s" % _format_time(definition.time_limit)
			if definition.time_limit > 0.0 else "No time limit")
	%DetailBriefing.text = definition.briefing
	for child in _stars.get_children():
		child.queue_free()
	for i in MAX_DIFFICULTY:
		var star := TextureRect.new()
		star.texture = STAR_ON if i < definition.difficulty else STAR_OFF
		star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		star.custom_minimum_size = Vector2(30, 30)
		_stars.add_child(star)


static func _format_time(seconds: float) -> String:
	var total := roundi(seconds)
	if total < 60:
		return "%d s" % total
	return "%d:%02d min" % [floori(total / 60.0), total % 60]
