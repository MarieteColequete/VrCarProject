class_name MapSandbox
extends Node
## Drives one map freely with the [DebugHud] over it: the map [constant PLAY_FILE] names, or else
## the first map the [MapCatalogue] finds. With [member dev_hud] set, or the file asking for it,
## a [DevHud] is added beside the DebugHud.

## An optional file naming the map to drive: section [code]play[/code], key [code]map[/code], the
## map's path; and key [code]dev_hud[/code], true to add the [DevHud].
const PLAY_FILE := "user://map_kit_play.cfg"
const DEV_HUD := preload("res://scenarios/debug/dev_hud.tscn")

@export var runner: ExamRunner
## Adds a [DevHud] whatever [constant PLAY_FILE] says.
@export var dev_hud := false
## Loads the map [method chosen_map] names when the sandbox starts; off to only add the overlays,
## such as over a scenario the runner loads itself.
@export var load_chosen_map := true

## The [DevHud], once added.
var dev: DevHud


func _ready() -> void:
	if dev_hud or dev_hud_wanted():
		add_dev_hud()
	if not load_chosen_map:
		return
	var path := chosen_map()
	if path.is_empty():
		push_error("No map to drive: %s names none and %s holds no map" % [PLAY_FILE,
			MapCatalogue.ROOT])
		return
	runner.load_map(load(path) as PackedScene)


## Adds a [DevHud] reading [member runner] beside the other overlays; once.
func add_dev_hud() -> DevHud:
	if dev == null:
		dev = DEV_HUD.instantiate()
		dev.runner = runner
		add_child(dev)
	return dev


## The path of the map to drive; empty for none.
static func chosen_map() -> String:
	var config := ConfigFile.new()
	if config.load(PLAY_FILE) == OK:
		var path: String = config.get_value("play", "map", "")
		if ResourceLoader.exists(path, "PackedScene"):
			return path
	var maps := MapCatalogue.scan()
	return maps[0].path if not maps.is_empty() else ""


## Whether [constant PLAY_FILE] asks for the [DevHud]: section [code]play[/code], key
## [code]dev_hud[/code]; false when the file or the key is missing.
static func dev_hud_wanted() -> bool:
	var config := ConfigFile.new()
	if config.load(PLAY_FILE) != OK:
		return false
	return bool(config.get_value("play", "dev_hud", false))
