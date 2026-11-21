extends Node
## Drives one map freely with the [DebugHud] over it: the map [constant PLAY_FILE] names, or else
## the first map the [MapCatalogue] finds.

## An optional file naming the map to drive: section [code]play[/code], key [code]map[/code], the
## map's path.
const PLAY_FILE := "user://map_kit_play.cfg"

@export var runner: ExamRunner


func _ready() -> void:
	var path := chosen_map()
	if path.is_empty():
		push_error("No map to drive: %s names none and %s holds no map" % [PLAY_FILE,
			MapCatalogue.ROOT])
		return
	runner.load_map(load(path) as PackedScene)


## The path of the map to drive; empty for none.
static func chosen_map() -> String:
	var config := ConfigFile.new()
	if config.load(PLAY_FILE) == OK:
		var path: String = config.get_value("play", "map", "")
		if ResourceLoader.exists(path, "PackedScene"):
			return path
	var maps := MapCatalogue.scan()
	return maps[0].path if not maps.is_empty() else ""
