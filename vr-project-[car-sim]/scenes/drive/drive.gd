extends Node
## Plays the scenario chosen in the main menu: the briefing, the attempt, then the result.
##
## It wraps the scenario framework's [ExamRunner] without changing it, and reaches the attempt
## only through the runner's [ExamSession] signals and commands. The briefing and the result are
## shown through a [MenuOverlay], on screen or on a VR panel. Run on its own from the editor, it
## drives the first scenario of the catalogue.

const DRIVE_PANEL := preload("res://ui/menus/drive_panel.tscn")
const BEGIN_ACTION := &"exam_begin"

var _overlay: MenuOverlay
var _panel  # drive_panel.gd

@onready var _runner: ExamRunner = $Runner


func _ready() -> void:
	var session := _runner.session
	session.briefing_started.connect(_on_briefing_started)
	session.started.connect(_close_panel)
	session.finished.connect(_on_finished)

	var definition := GameFlow.next_scenario
	if definition == null:
		var catalogue := ScenarioCatalogue.main()
		if catalogue and not catalogue.scenarios.is_empty():
			definition = catalogue.scenarios[0]
	_runner.load_definition(definition)


func _unhandled_input(event: InputEvent) -> void:
	# The scenario framework's own action begins the attempt from the briefing, also in VR where
	# the panel's buttons do not see keyboard or gamepad input.
	if _panel and _panel.is_briefing() and event.is_action_pressed(BEGIN_ACTION):
		get_viewport().set_input_as_handled()
		_runner.session.begin()


func _on_briefing_started(definition: ScenarioDefinition) -> void:
	_open_panel()
	_panel.show_briefing(definition)


func _on_finished(result: ScenarioResult) -> void:
	_open_panel()
	_panel.show_result(result)


func _open_panel() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _overlay:
		return
	_panel = DRIVE_PANEL.instantiate()
	_panel.begin_requested.connect(_runner.session.begin)
	_panel.retry_requested.connect(_on_retry_requested)
	_panel.scenarios_requested.connect(func() -> void: GameFlow.to_main_menu(get_tree(), true))
	_panel.main_menu_requested.connect(func() -> void: GameFlow.to_main_menu(get_tree()))
	_overlay = MenuOverlay.new()
	add_child(_overlay)
	_overlay.present(_panel)


func _close_panel() -> void:
	if _overlay:
		_overlay.queue_free()
	_overlay = null
	_panel = null
	if not XRManager.is_vr:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_retry_requested() -> void:
	# The runner rebuilds the scenario, which shows the briefing again.
	_close_panel()
	_runner.session.restart()
