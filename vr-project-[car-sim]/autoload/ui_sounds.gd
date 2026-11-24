extends Node
## Autoload "UISounds".
##
## Automatically plays UI sounds for every button, checkbox, slider and option
## stepper that enters the scene tree, in any scene. Nothing has to be wired up
## by hand. To silence a specific control, add the metadata [code]no_ui_sound[/code]
## to it (any value) in the inspector.

const HOVER_SOUND := preload("res://assets/ui/kenney_ui-pack/Sounds/tap-a.ogg")
const CLICK_SOUND := preload("res://assets/ui/kenney_ui-pack/Sounds/click-a.ogg")
const TOGGLE_SOUND := preload("res://assets/ui/kenney_ui-pack/Sounds/switch-a.ogg")
const TICK_SOUND := preload("res://assets/ui/kenney_ui-pack/Sounds/tap-b.ogg")

const BUS := &"SFX"
const MIN_INTERVAL_MSEC := 60  # Avoids machine-gun sounds when dragging or hovering fast.

var _players: Dictionary = {}  # AudioStream -> AudioStreamPlayer
var _last_played: Dictionary = {}  # AudioStream -> msec


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # Menus also make sounds while the game is paused.
	for stream in [HOVER_SOUND, CLICK_SOUND, TOGGLE_SOUND, TICK_SOUND]:
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.bus = BUS
		player.max_polyphony = 3
		add_child(player)
		_players[stream] = player
	get_tree().node_added.connect(_on_node_added)


func play_hover() -> void:
	_play(HOVER_SOUND)


func play_click() -> void:
	_play(CLICK_SOUND)


func play_toggle() -> void:
	_play(TOGGLE_SOUND)


func _play(stream: AudioStream, volume_db := 0.0) -> void:
	var now := Time.get_ticks_msec()
	if now - int(_last_played.get(stream, -1000)) < MIN_INTERVAL_MSEC:
		return
	_last_played[stream] = now
	var player: AudioStreamPlayer = _players[stream]
	player.volume_db = volume_db
	player.play()


func _on_node_added(node: Node) -> void:
	if not node is Control or node.has_meta(&"no_ui_sound"):
		return
	if node is BaseButton:
		var button := node as BaseButton
		button.mouse_entered.connect(_on_button_hovered.bind(button))
		button.focus_entered.connect(_on_button_hovered.bind(button))
		if button.toggle_mode:
			button.toggled.connect(func(_on: bool) -> void: play_toggle())
		else:
			button.pressed.connect(play_click)
	elif node is Slider:
		var slider := node as Slider
		slider.mouse_entered.connect(_play.bind(HOVER_SOUND, -6.0))
		slider.focus_entered.connect(_play.bind(HOVER_SOUND, -6.0))
		slider.value_changed.connect(func(_value: float) -> void: _play(TICK_SOUND, -4.0))
	elif node.has_signal(&"item_selected"):
		# OptionStepper (ui/components/option_stepper.gd) and OptionButton.
		node.focus_entered.connect(_play.bind(HOVER_SOUND, -6.0))
		node.item_selected.connect(func(_index: int) -> void: play_toggle())


func _on_button_hovered(button: BaseButton) -> void:
	if not button.disabled:
		play_hover()
