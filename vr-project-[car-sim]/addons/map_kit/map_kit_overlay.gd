@tool
class_name MapKitOverlay
extends RefCounted
## Draws over the editor's 3D view while a map is open: an arrow every
## [constant ARROW_SPACING] metres along each lane, each lane's end green when it leads on and red
## when it leads nowhere, a plus on every open road end, spawn numbers, zone names, checkpoints
## and a dashed line from each road user to the checkpoint it drives to, a badge with the map's
## title and its problem count, and the placing hint. What to draw is worked out in the
## map's space by [method marks], away from the editor, and only projected when drawn.

const ARROW_SPACING := 10.0
const ARROW := Color(0.55, 0.7, 1.0, 0.9)
const LINKED := Color(0.35, 1.0, 0.5)
const DEAD_END := Color(1.0, 0.35, 0.3)
const OPEN_END := Color(1.0, 0.85, 0.3)
const SPAWN := Color(0.3, 1.0, 0.45)
const ZONE := Color(1.0, 0.65, 0.25)
const BADGE := Color(0, 0, 0, 0.55)
const ROUTE := Color(0.95, 0.35, 0.9)

## The marks of the open map, from the last [method refresh].
var _marks := {}


## Works out the marks of [param road_map] again; nothing when it is null.
func refresh(road_map: RoadMap) -> void:
	_marks = marks(road_map) if road_map else {}


## What to draw for [param road_map], in its space:
## [code]{arrows: [[point, direction]], ends: [[point, leads_on]], open: [point],
## labels: [[point, text, colour]], routes: [[from, to]]}[/code].
static func marks(road_map: RoadMap) -> Dictionary:
	var out := {arrows = [], ends = [], open = [], labels = [], routes = []}
	var spawn_number := 0
	for node in road_map.nodes():
		if node is TrafficLane:
			var lane := node as TrafficLane
			var length := lane.length()
			if length <= 0.0:
				continue
			var into := MapKitTools.to_map(lane, road_map)
			var at := minf(ARROW_SPACING / 2.0, length / 2.0)
			while at < length:
				var point := into * lane.curve.sample_baked(at)
				var ahead := into * lane.curve.sample_baked(minf(at + 0.5, length)) - point
				out.arrows.append([point, ahead.normalized()])
				at += ARROW_SPACING
			out.ends.append([into * lane.curve.sample_baked(length), not lane.next.is_empty()])
		elif node is MapSpawn:
			spawn_number += 1
			var spawn := node as MapSpawn
			var text := "%d %s" % [spawn_number, spawn.label if not spawn.label.is_empty()
				else String(spawn.name)]
			out.labels.append([MapKitTools.to_map(spawn, road_map).origin, text, SPAWN])
		elif node is ScriptedAgent and (node as ScriptedAgent).destination:
			var agent := node as ScriptedAgent
			var from := MapKitTools.to_map(agent, road_map).origin
			var to := MapKitTools.to_map(agent.destination, road_map).origin
			out.routes.append([from, to])
			out.labels.append([from, "to %s" % agent.destination.name, ROUTE])
		elif node is Checkpoint:
			var checkpoint := node as Checkpoint
			out.labels.append([MapKitTools.to_map(checkpoint, road_map).origin,
				checkpoint.label if not checkpoint.label.is_empty() else String(checkpoint.name),
				ROUTE])
		elif node is TriggerZone:
			out.labels.append([MapKitTools.to_map(node, road_map).origin, String(node.name), ZONE])
	for end in MapKitTools.road_ends(road_map):
		out.open.append(end.transform.origin)
	return out


## Draws on [param control], the overlay of the 3D view seen by [param camera]: the marks of
## [param road_map] when it is set, the badge counting [param problems], and [param hint].
func draw(control: Control, camera: Camera3D, road_map: RoadMap, problems: Array[Dictionary],
		hint: String) -> void:
	var font := control.get_theme_default_font()
	var size := control.get_theme_default_font_size()
	if road_map and not _marks.is_empty():
		var to_world := road_map.global_transform
		for arrow: Array in _marks.arrows:
			_arrow(control, camera, to_world * (arrow[0] as Vector3),
				to_world.basis * (arrow[1] as Vector3))
		for end: Array in _marks.ends:
			var at: Variant = _screen(camera, to_world * (end[0] as Vector3))
			if at != null:
				control.draw_circle(at, 4.0, LINKED if end[1] else DEAD_END)
		for point: Vector3 in _marks.open:
			var at: Variant = _screen(camera, to_world * point)
			if at != null:
				control.draw_line(at - Vector2(7, 0), at + Vector2(7, 0), OPEN_END, 2.5)
				control.draw_line(at - Vector2(0, 7), at + Vector2(0, 7), OPEN_END, 2.5)
		for route: Array in _marks.routes:
			var from: Variant = _screen(camera, to_world * (route[0] as Vector3))
			var to: Variant = _screen(camera, to_world * (route[1] as Vector3))
			if from != null and to != null:
				control.draw_dashed_line(from, to, ROUTE, 2.0, 8.0)
		for label: Array in _marks.labels:
			var at: Variant = _screen(camera, to_world * (label[0] as Vector3))
			if at != null:
				_text(control, font, size, at + Vector2(6, -6), label[1], label[2])
	if road_map:
		_badge(control, font, size, road_map, problems)
	if not hint.is_empty():
		var width := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
		var at := Vector2((control.size.x - width) / 2.0, control.size.y - 24)
		control.draw_rect(Rect2(at - Vector2(10, size + 2), Vector2(width + 20, size + 14)), BADGE)
		control.draw_string(font, at, hint, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.WHITE)


func _badge(control: Control, font: Font, size: int, road_map: RoadMap,
		problems: Array[Dictionary]) -> void:
	var warnings := problems.filter(func(p: Dictionary) -> bool:
		return p.severity == MapKitTools.WARNING).size()
	var title := road_map.title if not road_map.title.is_empty() else String(road_map.name)
	var count := "no problems" if problems.is_empty() \
		else "%d warnings, %d notices" % [warnings, problems.size() - warnings]
	var text := "%s  ·  %s" % [title, count]
	var width := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var at := Vector2(control.size.x - width - 24, 48)
	control.draw_rect(Rect2(at - Vector2(10, size + 2), Vector2(width + 20, size + 12)), BADGE)
	var colour := LINKED if problems.is_empty() else (DEAD_END if warnings > 0 else OPEN_END)
	control.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, colour)


func _arrow(control: Control, camera: Camera3D, point: Vector3, direction: Vector3) -> void:
	var tail: Variant = _screen(camera, point - direction * 0.9)
	var head: Variant = _screen(camera, point + direction * 0.9)
	if tail == null or head == null:
		return
	var along: Vector2 = (head as Vector2) - (tail as Vector2)
	if along.length() < 3.0:
		return
	var back := -along.normalized() * minf(8.0, along.length() * 0.6)
	control.draw_line(tail, head, ARROW, 2.0)
	control.draw_line(head, head + back.rotated(0.5), ARROW, 2.0)
	control.draw_line(head, head + back.rotated(-0.5), ARROW, 2.0)


static func _text(control: Control, font: Font, size: int, at: Vector2, text: String,
		colour: Color) -> void:
	control.draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 4, Color.BLACK)
	control.draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, colour)


## Where [param point] shows on the view; null when it is behind the camera.
static func _screen(camera: Camera3D, point: Vector3) -> Variant:
	if camera.is_position_behind(point):
		return null
	return camera.unproject_position(point)
