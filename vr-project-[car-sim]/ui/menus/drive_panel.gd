extends MenuScreen
## The drive scene's two panels: the briefing before an attempt and the result after it. It only
## shows what it is given and emits what the player chose; the drive scene talks to the session.

signal begin_requested
signal retry_requested
signal scenarios_requested
signal main_menu_requested

const PASS_COLOR := Color(0.12, 0.62, 0.36)
const FAIL_COLOR := Color(0.85, 0.2, 0.25)
const REASONS := {
	&"completed": "Goal reached",
	&"eliminated": "Ended by an eliminating fault",
	&"timeout": "The time limit ran out",
	&"aborted": "The attempt was stopped",
}
const DESKTOP_HINT := "Enter / Start: begin"
const VR_HINT := "Point with a controller and pull the trigger"

@onready var _briefing_page: Control = %BriefingPage
@onready var _result_page: Control = %ResultPage


func _ready() -> void:
	super()
	%BeginButton.pressed.connect(begin_requested.emit)
	%BriefingMenuButton.pressed.connect(main_menu_requested.emit)
	%RetryButton.pressed.connect(retry_requested.emit)
	%ScenariosButton.pressed.connect(scenarios_requested.emit)
	%ResultMenuButton.pressed.connect(main_menu_requested.emit)
	_result_page.hide()


func default_focus() -> Control:
	return %BeginButton if _briefing_page.visible else %RetryButton


## True while the briefing is shown.
func is_briefing() -> bool:
	return _briefing_page.visible


func show_briefing(definition: ScenarioDefinition) -> void:
	_result_page.hide()
	_briefing_page.show()
	%BriefingCategory.text = definition.category
	%BriefingTitle.text = definition.title
	%BriefingText.text = definition.briefing
	%BriefingHint.text = VR_HINT if XRManager.is_vr else DESKTOP_HINT
	focus_for_keyboard(%BeginButton)


func show_result(result: ScenarioResult) -> void:
	_briefing_page.hide()
	_result_page.show()
	%ResultTitle.text = "Passed" if result.passed else "Failed"
	%ResultTitle.add_theme_color_override(&"font_color", PASS_COLOR if result.passed else FAIL_COLOR)
	%ResultScenario.text = result.scenario_title
	var stats := "%s  ·  %.1f s  ·  %d fault%s" % [
		REASONS.get(result.reason, String(result.reason)), result.duration,
		result.faults.size(), "" if result.faults.size() == 1 else "s"]
	if result.step_count > 1:
		stats += "  ·  steps %d / %d" % [result.steps_completed, result.step_count]
	%ResultStats.text = stats

	var list: VBoxContainer = %FaultList
	for child in list.get_children():
		child.queue_free()
	if result.faults.is_empty():
		list.add_child(_fault_line("No faults recorded."))
	for fault in result.faults:
		list.add_child(_fault_line("%s  (%s, at %.0f s)" % [fault.def.title, fault.def.tier, fault.time]))
	focus_for_keyboard(%RetryButton)


func _fault_line(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override(&"font_size", 22)
	return label
