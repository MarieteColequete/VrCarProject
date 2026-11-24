class_name GameFlow
extends RefCounted
## Moves between the main menu and the drive scene, carrying what the next scene needs across the
## scene change: the scenario to drive, and whether the menu opens on the scenario list.

const MAIN_MENU := "res://scenes/main_menu/main_menu.tscn"
const DRIVE := "res://scenes/drive/drive.tscn"

## The scenario the drive scene loads next.
static var next_scenario: ScenarioDefinition
## Makes the main menu open on its scenario list once.
static var open_scenario_list := false


static func start_scenario(tree: SceneTree, definition: ScenarioDefinition) -> void:
	next_scenario = definition
	tree.paused = false
	tree.change_scene_to_file(DRIVE)


static func to_main_menu(tree: SceneTree, show_scenarios := false) -> void:
	open_scenario_list = show_scenarios
	tree.paused = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	tree.change_scene_to_file(MAIN_MENU)
