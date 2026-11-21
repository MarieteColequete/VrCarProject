@tool
class_name RoadMap
extends Node3D
## The root of a map scene: the world only, with its roads, markings, lanes, lights, traffic,
## signs, props, and the places a car may start. A map holds no [Check]s; how a drive is judged is
## a scenario's. Maps live in [code]res://maps/<name>/<name>.tscn[/code], where the
## [MapCatalogue] finds them, and each can be driven on its own in free drive or instanced as the
## [code]Map[/code] child of a [Scenario].

## A stable name for saves and links, such as [code]stop_junction[/code]; the folder's name when
## empty.
@export var id: StringName
@export var title: String
@export_multiline var description: String


## The map's spawns, in tree order; the first is where free drive starts.
func spawns() -> Array[MapSpawn]:
	var found: Array[MapSpawn] = []
	for node in nodes():
		if node is MapSpawn:
			found.append(node)
	return found


## The map's nodes below the root, in tree order, internal children left out.
func nodes() -> Array[Node]:
	var out: Array[Node] = []
	Scenario.collect(self, out)
	return out


func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var has_spawn := false
	for node in nodes():
		if node is MapSpawn:
			has_spawn = true
		elif node is Check:
			warnings.append("%s is a check; checks belong to a scenario, not to a map." % node.name)
		elif node is TrafficLane:
			var lane := node as TrafficLane
			if lane.curve == null or lane.curve.point_count < 2:
				warnings.append("The lane %s has no curve." % lane.name)
	if not has_spawn:
		warnings.append("Add a MapSpawn where the car starts.")
	return warnings
