class_name DebugHud
extends CanvasLayer
## A flat overlay for trying scenarios while building them: the briefing, the current step, the
## time against the limit, faults as they are committed, how other road users react, a
## performance readout, and the result. It only listens to the [ExamRunner], its [ExamSession], and the scenario's
## [ScriptedAgent]s, so it also shows how a UI uses them. Keys: exam_begin
## starts the attempt after the briefing, exam_restart restarts it, exam_next_scenario moves to
## the next scenario of the [ScenarioCatalogue], and toggle_debug_hud hides the overlay; the hints
## it shows are read from the input map, so they follow any rebinding. It hides itself while a
## headset drives the view, where a UI of its own applies.

const TIER_COLOURS := {&"critical": Color(1.0, 0.35, 0.3), &"serious": Color(1.0, 0.65, 0.2),
	&"minor": Color(1.0, 0.9, 0.4)}
## How many recent lines the feed keeps.
const FEED_LENGTH := 8
const REACTION_COLOUR := Color(0.75, 0.75, 0.75)
const BUTTON_NAMES := {JOY_BUTTON_A: "A", JOY_BUTTON_B: "B", JOY_BUTTON_X: "X", JOY_BUTTON_Y: "Y",
	JOY_BUTTON_BACK: "Back", JOY_BUTTON_START: "Start", JOY_BUTTON_LEFT_STICK: "Left stick click",
	JOY_BUTTON_RIGHT_STICK: "Right stick click", JOY_BUTTON_LEFT_SHOULDER: "LB",
	JOY_BUTTON_RIGHT_SHOULDER: "RB", JOY_BUTTON_DPAD_UP: "D-pad up",
	JOY_BUTTON_DPAD_DOWN: "D-pad down", JOY_BUTTON_DPAD_LEFT: "D-pad left",
	JOY_BUTTON_DPAD_RIGHT: "D-pad right"}

@export var runner: ExamRunner
@export var catalogue: ScenarioCatalogue = preload("res://scenarios/catalogue.tres")

var title_label: Label
var step_label: Label
var time_label: Label
## Where the frame's time goes: the frame, physics, and the traffic system's share of the main
## thread, with the road users it runs.
var performance_label: Label
var feed: VBoxContainer
var message_panel: PanelContainer
var message_label: Label


func _ready() -> void:
	_build()
	if runner == null:
		push_error("DebugHud needs its runner set")
		return
	var session := runner.session
	session.briefing_started.connect(_on_briefing)
	session.started.connect(_on_started)
	session.step_changed.connect(_on_step)
	session.fault_committed.connect(_on_fault)
	session.finished.connect(_on_finished)
	runner.scenario_loaded.connect(_on_scenario_loaded)
	get_tree().node_added.connect(_on_node_added)


func _process(_delta: float) -> void:
	if XRServer.primary_interface and XRServer.primary_interface.is_initialized():
		visible = false
	if runner == null or runner.session.definition == null:
		return
	var session := runner.session
	var limit := session.definition.time_limit
	time_label.text = "%.1f s" % session.elapsed if limit <= 0.0 \
		else "%.1f / %.0f s" % [session.elapsed, limit]
	performance_label.text = _performance_text()


func _unhandled_input(event: InputEvent) -> void:
	if runner == null:
		return
	if event.is_action_pressed(&"toggle_debug_hud"):
		visible = not visible
	elif event.is_action_pressed(&"exam_begin"):
		runner.session.begin()
	elif event.is_action_pressed(&"exam_restart"):
		runner.session.restart()
	elif event.is_action_pressed(&"exam_next_scenario"):
		next_scenario()
	else:
		return
	get_viewport().set_input_as_handled()


## Loads the scenario after the current one in the catalogue, wrapping round to the first.
func next_scenario() -> void:
	if catalogue == null or catalogue.scenarios.is_empty():
		return
	var index := -1
	if runner.scenario and runner.scenario.definition:
		index = catalogue.scenarios.find(catalogue.find(runner.scenario.definition.id))
	runner.load_definition(catalogue.scenarios[(index + 1) % catalogue.scenarios.size()])


## The keys and buttons bound to [param action], as the input map has them: "Enter or Start".
static func binding_text(action: StringName) -> String:
	var names := PackedStringArray()
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			names.append(event.as_text_physical_keycode())
		elif event is InputEventJoypadButton:
			names.append(BUTTON_NAMES.get(event.button_index, "Button %d" % event.button_index))
	return " or ".join(names) if not names.is_empty() else String(action)


## The main thread's process time, the physics process time, and the traffic system's main thread
## time (snapshot and applying) and any wait for its threads, in milliseconds.
func _performance_text() -> String:
	var text := "main %.1f ms  physics %.1f ms" % [
		Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
		Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0]
	var root := get_tree().root
	if root.has_meta(TrafficSystem.META_KEY):
		var system: TrafficSystem = root.get_meta(TrafficSystem.META_KEY)
		if is_instance_valid(system) and system.count() > 0:
			text += "  traffic %.2f ms, waiting %.2f ms, road users %d" % [
				(system.think_usec + system.commit_usec - system.wait_usec) / 1000.0,
				system.wait_usec / 1000.0, system.count()]
	return text


func _on_briefing(definition: ScenarioDefinition) -> void:
	title_label.text = definition.title
	step_label.text = ""
	_show_message("%s\n\n%s\n\n%s" % [definition.title, definition.briefing,
		"%s to begin" % binding_text(&"exam_begin") if not runner.autostart else ""])


func _on_started() -> void:
	message_panel.visible = false


func _on_step(step: ScenarioStep) -> void:
	step_label.text = step.instruction if not step.instruction.is_empty() else step.title


func _on_fault(fault: FaultRecord) -> void:
	_add_line("%.1f s  %s" % [fault.time, fault.def.title],
		TIER_COLOURS.get(fault.def.tier, Color.WHITE))


func _on_scenario_loaded(scenario: Scenario, _car: Node3D) -> void:
	_clear_feed()
	for node in scenario.find_children("*", "", true, false):
		if node is ScriptedAgent:
			_watch_agent(node)


func _on_node_added(node: Node) -> void:
	if node is ScriptedAgent and runner and runner.scenario and runner.scenario.is_ancestor_of(node):
		_watch_agent(node)


func _watch_agent(agent: ScriptedAgent) -> void:
	if agent.reacted.is_connected(_on_reacted.bind(agent)):
		return
	agent.reacted.connect(_on_reacted.bind(agent))
	agent.forced_to_brake.connect(_on_forced.bind(agent))


func _on_reacted(kind: StringName, cause: Node3D, agent: ScriptedAgent) -> void:
	if kind == &"resumed" or runner.session.state != ExamSession.State.RUNNING:
		return
	var what := String(kind).replace("_", " ")
	_add_line("%.1f s  %s %s%s" % [runner.session.elapsed, agent.name, what,
		" for %s" % cause.name if cause else ""], REACTION_COLOUR)


func _on_forced(_cause: Node3D, deceleration: float, agent: ScriptedAgent) -> void:
	_add_line("%.1f s  %s braked hard (%.1f m/s²)" % [runner.session.elapsed, agent.name,
		deceleration], REACTION_COLOUR)


func _add_line(text: String, colour: Color) -> void:
	var line := Label.new()
	line.text = text
	line.add_theme_color_override(&"font_color", colour)
	feed.add_child(line)
	while feed.get_child_count() > FEED_LENGTH:
		var oldest := feed.get_child(0)
		feed.remove_child(oldest)
		oldest.queue_free()


func _on_finished(result: ScenarioResult) -> void:
	var data := result.to_dict()
	var lines := PackedStringArray()
	lines.append("%s: %s" % [data.scenario.title, "PASSED" if data.passed else "FAILED"])
	lines.append("%s after %.1f s, steps %d of %d" % [String(data.reason).capitalize(), data.duration,
		data.steps_completed, data.step_count])
	for tier: Dictionary in data.tiers:
		var limit := "eliminating" if tier.eliminating \
			else ("no limit" if tier.max_allowed < 0 else "%d allowed" % tier.max_allowed)
		lines.append("%s: %d (%s)" % [tier.title if not tier.title.is_empty() else tier.id,
			tier.count, limit])
	lines.append("")
	lines.append("%s to restart, %s for the next scenario" % [binding_text(&"exam_restart"),
		binding_text(&"exam_next_scenario")])
	_show_message("\n".join(lines))


func _show_message(text: String) -> void:
	message_label.text = text.strip_edges()
	message_panel.visible = true


func _clear_feed() -> void:
	for child in feed.get_children():
		feed.remove_child(child)
		child.queue_free()


func _build() -> void:
	var status := PanelContainer.new()
	status.position = Vector2(16, 16)
	add_child(status)
	var column := VBoxContainer.new()
	status.add_child(column)
	title_label = Label.new()
	title_label.add_theme_font_size_override(&"font_size", 20)
	step_label = Label.new()
	time_label = Label.new()
	performance_label = Label.new()
	performance_label.modulate = Color(1, 1, 1, 0.6)
	feed = VBoxContainer.new()
	var keys := Label.new()
	keys.text = "%s begin   %s restart   %s next   %s hide" % [_first_key(&"exam_begin"),
		_first_key(&"exam_restart"), _first_key(&"exam_next_scenario"), _first_key(&"toggle_debug_hud")]
	keys.modulate = Color(1, 1, 1, 0.6)
	for node: Control in [title_label, step_label, time_label, performance_label, feed, keys]:
		column.add_child(node)

	message_panel = PanelContainer.new()
	message_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	message_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	message_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	message_panel.custom_minimum_size = Vector2(520, 0)
	message_panel.visible = false
	add_child(message_panel)
	message_label = Label.new()
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_panel.add_child(message_label)


static func _first_key(action: StringName) -> String:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			return event.as_text_physical_keycode()
	return String(action)
