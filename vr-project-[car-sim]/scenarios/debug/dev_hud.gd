class_name DevHud
extends CanvasLayer
## A developer's overlay for trying maps while building them: the frame rate with a graph of the
## last frames and where their time goes; the car's speed, position, heading, and nearest lane
## with its limit; the road users near it, the lights, and the session; and tools to slow down,
## speed up, pause and step the simulation, move the car to another spawn, fly a [FreeCamera], and
## show the world's trigger zones and lanes in 3D (the panel's check box). Like the [DebugHud], it
## reads the runner's [World] and never writes it: it reads the [ExamRunner] and the car's
## [VehicleProbe], and drives the runner, the tree's pause, and the engine's time scale only
## through their public calls. Keys:
## dev_toggle_hud, dev_free_camera, dev_slower, dev_faster, dev_pause, dev_step, and
## dev_next_spawn. It runs while the tree is paused, and hides itself while a headset drives the
## view.

## The time scales [method slower] and [method faster] step through.
const TIME_SCALES: Array[float] = [0.25, 0.5, 1.0, 2.0]
## How many frames the frame time graph shows.
const GRAPH_FRAMES := 120
## Road users within this many metres of the car are listed.
const NEAR_RADIUS := 50.0
const GRAPH_SIZE := Vector2(240, 48)
## The frame time at the graph's top, in milliseconds.
const GRAPH_TOP_MS := 33.3
const LIGHT_NAMES := ["red", "red-amber", "green", "amber"]
const ZONE_COLOUR := Color(1.0, 0.4, 0.8)
const LANE_COLOUR := Color(1.0, 0.85, 0.2)
const PATH_COLOUR := Color(0.6, 0.8, 1.0)
const KEYS: Array[StringName] = [&"dev_toggle_hud", &"dev_free_camera", &"dev_slower",
	&"dev_faster", &"dev_pause", &"dev_step", &"dev_next_spawn"]

@export var runner: ExamRunner

## Which of [constant TIME_SCALES] is in use.
var time_scale_index := TIME_SCALES.find(1.0)
## Whether the world's zones and lanes are drawn in 3D while the overlay is shown; the check box
## on the panel switches it.
@export var overlay_shown := true
var free_camera: FreeCamera

var fps_label: Label
var graph: Control
var performance_label: Label
var speed_label: Label
var position_label: Label
var lane_label: Label
var users_label: Label
var lights_label: Label
var session_label: Label
var tools_label: Label

## Real frame times, in milliseconds, oldest first.
var _frame_ms := PackedFloat32Array()
var _last_usec := 0
## Set by [method step_once]: pause again after the next tick.
var _stepping := false
var _spawn_counts := {}
var _overlay: MeshInstance3D
var _overlay_mesh: ImmediateMesh


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Its physics step pauses again after a single step, so it runs after every other node's.
	process_physics_priority = 1000


func _ready() -> void:
	_build()
	if runner == null:
		push_error("DevHud needs its runner set")
		return
	runner.scenario_loaded.connect(func(_s: Scenario, _c: Node3D) -> void:
		set_overlay(visible and overlay_shown))
	set_overlay(visible and overlay_shown)
	var parent := get_parent()
	if parent:
		for sibling in parent.get_children():
			if sibling is DebugHud:
				_hint(sibling)


func _hint(hud: DebugHud) -> void:
	if hud.is_node_ready():
		hud.add_key_hints(key_hint_text())
	else:
		hud.ready.connect(_hint.bind(hud), CONNECT_ONE_SHOT)


## The DevHud's keys as the input map has them, for the [DebugHud]'s hint line.
static func key_hint_text() -> String:
	return "%s dev   %s camera   %s/%s speed   %s pause   %s step   %s spawn" % [
		DebugHud.first_key(&"dev_toggle_hud"), DebugHud.first_key(&"dev_free_camera"),
		DebugHud.first_key(&"dev_slower"), DebugHud.first_key(&"dev_faster"),
		DebugHud.first_key(&"dev_pause"), DebugHud.first_key(&"dev_step"),
		DebugHud.first_key(&"dev_next_spawn")]


func _physics_process(_delta: float) -> void:
	if _stepping:
		_stepping = false
		get_tree().paused = true


func _process(_delta: float) -> void:
	if _xr_active():
		visible = false
		return
	var now := Time.get_ticks_usec()
	if _last_usec > 0:
		_frame_ms.append((now - _last_usec) / 1000.0)
		if _frame_ms.size() > GRAPH_FRAMES:
			_frame_ms.remove_at(0)
	_last_usec = now
	if not visible:
		return
	refresh()


## Fills every readout from the runner and its world now.
func refresh() -> void:
	var ms := _frame_ms[-1] if not _frame_ms.is_empty() else 0.0
	fps_label.text = "FPS %d   frame %.1f ms" % [Engine.get_frames_per_second(), ms]
	graph.queue_redraw()
	performance_label.text = DebugHud.performance_text(runner)
	tools_label.text = "time ×%s%s%s%s" % [_scale_text(), "   PAUSED" if get_tree().paused else "",
		"   free camera" if free_camera and free_camera.is_open() else "",
		"   spawn %d" % runner.map_spawn if runner and runner.map_scene else ""]
	var world := runner.world() if runner else null
	var probe := VehicleProbe.of(runner.car) if runner else null
	if world == null or probe == null:
		for label: Label in [speed_label, position_label, lane_label, users_label, lights_label,
				session_label]:
			label.text = ""
		return
	var position := probe.global_position
	var forward := probe.forward()
	var vehicle := Schema.single(world, Schema.VEHICLE)
	var speed: float = world.get_value(Schema.VEHICLE, vehicle, &"speed") if vehicle else 0.0
	speed_label.text = "%.1f km/h" % (speed * 3.6)
	position_label.text = "position %.1f, %.1f, %.1f   heading %03.0f°" % [position.x,
		position.y, position.z, heading_degrees(forward)]
	lane_label.text = _lane_text(world, position)
	users_label.text = _users_text(world, position)
	lights_label.text = _lights_text(world)
	session_label.text = _session_text()


## The compass heading of [param forward], in degrees: 0 along -Z, 90 along +X.
static func heading_degrees(forward: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(forward.x, -forward.z)), 360.0)


## The lane of [param world] nearest [param point]: its entity, how far along it, and how far
## off; entity 0 when the world has no lanes.
static func nearest_lane(world: World, point: Vector3) -> Dictionary:
	var best := {lane = 0, offset = 0.0, distance = INF}
	var lanes: Dictionary = world.resources.get(Schema.LANES, {})
	for id: int in lanes:
		var lane: LaneData = lanes[id]
		if not lane.is_lane:
			continue
		var projected := lane.project(point)
		if projected.y < best.distance:
			best = {lane = id, offset = projected.x, distance = projected.y}
	return best


func _lane_text(world: World, point: Vector3) -> String:
	var nearest := nearest_lane(world, point)
	if nearest.lane == 0:
		return "no lane"
	var lane: LaneData = world.resources[Schema.LANES][nearest.lane]
	var limit := "no limit" if is_inf(lane.speed_limit) \
		else "limit %.0f km/h" % (lane.speed_limit * 3.6)
	return "lane %s, %.1f m off, %.0f m along, %s" % [lane.name, nearest.distance,
		nearest.offset, limit]


func _users_text(world: World, point: Vector3) -> String:
	var agents := world.store(Schema.AGENT)
	if agents == null:
		return "road users: none"
	var positions: Array = agents.column(&"position")
	var names: Array = agents.column(&"name")
	var near: Array[Vector2] = []
	for row in agents.size():
		var d := point.distance_to(positions[row])
		if d <= NEAR_RADIUS:
			near.append(Vector2(d, row))
	near.sort()
	var parts := PackedStringArray()
	for entry in near.slice(0, 5):
		parts.append("%s %.0f m" % [names[int(entry.y)], entry.x])
	return "road users within %.0f m: %d of %d%s" % [NEAR_RADIUS, near.size(), agents.size(),
		("  (" + ", ".join(parts) + ")") if not parts.is_empty() else ""]


func _lights_text(world: World) -> String:
	var lights := world.store(Schema.LIGHT)
	if lights == null or lights.size() == 0:
		return "lights: none"
	var names: Array = lights.column(&"name")
	var states: Array = lights.column(&"state")
	var parts := PackedStringArray()
	for row in mini(lights.size(), 6):
		parts.append("%s %s" % [names[row], LIGHT_NAMES[states[row]]])
	return "lights: %s%s" % [", ".join(parts), " …" if lights.size() > 6 else ""]


func _session_text() -> String:
	var session := runner.session
	var counts := {}
	for fault: FaultRecord in session.faults:
		counts[fault.def.tier] = counts.get(fault.def.tier, 0) + 1
	var parts := PackedStringArray()
	for tier: StringName in counts:
		parts.append("%s %d" % [tier, counts[tier]])
	return "session %s, %.1f s, faults %s" % [
		String(ExamSession.State.keys()[session.state]).to_lower(), session.elapsed,
		", ".join(parts) if not parts.is_empty() else "none"]


func _scale_text() -> String:
	return str(TIME_SCALES[time_scale_index])


func _unhandled_input(event: InputEvent) -> void:
	if runner == null or _xr_active():
		return
	if event.is_action_pressed(&"dev_toggle_hud"):
		visible = not visible
		set_overlay(visible and overlay_shown)
	elif event.is_action_pressed(&"dev_free_camera"):
		toggle_free_camera()
	elif event.is_action_pressed(&"dev_slower"):
		slower()
	elif event.is_action_pressed(&"dev_faster"):
		faster()
	elif event.is_action_pressed(&"dev_pause"):
		toggle_pause()
	elif event.is_action_pressed(&"dev_step"):
		step_once()
	elif event.is_action_pressed(&"dev_next_spawn"):
		teleport(runner.map_spawn + 1)
	else:
		return
	get_viewport().set_input_as_handled()


## Sets the engine's time scale to [constant TIME_SCALES] entry [param index], clamped.
func set_time_scale(index: int) -> void:
	time_scale_index = clampi(index, 0, TIME_SCALES.size() - 1)
	Engine.time_scale = TIME_SCALES[time_scale_index]


func slower() -> void:
	set_time_scale(time_scale_index - 1)


func faster() -> void:
	set_time_scale(time_scale_index + 1)


## Pauses the tree, or lets it go on.
func toggle_pause() -> void:
	_stepping = false
	get_tree().paused = not get_tree().paused


## While paused, lets exactly one physics tick run, then pauses again.
func step_once() -> void:
	if not get_tree().paused:
		return
	_stepping = true
	get_tree().paused = false


## Restarts free drive with the car at the map's spawn [param index], wrapping round the map's
## spawns; does nothing while a scenario, not a map, is loaded.
func teleport(index: int) -> void:
	if runner == null or runner.map_scene == null:
		return
	var count := spawn_count(runner.map_scene)
	if count == 0:
		return
	runner.load_map(runner.map_scene, posmod(index, count))


## How many [MapSpawn]s the map [param scene] holds; counted once per scene.
func spawn_count(scene: PackedScene) -> int:
	if not _spawn_counts.has(scene):
		var road_map := scene.instantiate() as RoadMap
		_spawn_counts[scene] = road_map.spawns().size() if road_map else 0
		if road_map:
			road_map.free()
	return _spawn_counts[scene]


## Flies a [FreeCamera], pausing the drive, or gives the view back to the driver.
func toggle_free_camera() -> void:
	if free_camera == null:
		free_camera = FreeCamera.new()
		free_camera.name = "FreeCamera"
		add_child(free_camera)
	if free_camera.is_open():
		free_camera.close()
	else:
		free_camera.open()


## Shows or hides the world's trigger zones and lanes in 3D.
func set_overlay(shown: bool) -> void:
	if shown:
		rebuild_overlay()
	if _overlay:
		_overlay.visible = shown


func toggle_overlay() -> void:
	overlay_shown = not overlay_shown
	set_overlay(visible and overlay_shown)


## Draws the world's zones as boxes and its lanes as lines with arrows along their direction.
func rebuild_overlay() -> void:
	if _overlay == null:
		_overlay_mesh = ImmediateMesh.new()
		_overlay = MeshInstance3D.new()
		_overlay.name = "Overlay"
		_overlay.mesh = _overlay_mesh
		_overlay.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.vertex_color_use_as_albedo = true
		material.no_depth_test = true
		_overlay.material_override = material
		add_child(_overlay)
	_overlay_mesh.clear_surfaces()
	var world := runner.world() if runner else null
	if world == null:
		return
	var points := PackedVector3Array()
	var colours := PackedColorArray()
	var zones := world.store(Schema.ZONE)
	if zones:
		var transforms: Array = zones.column(&"transform")
		var halves: Array = zones.column(&"half")
		for row in zones.size():
			_box_lines(transforms[row], halves[row], points, colours)
	var lanes: Dictionary = world.resources.get(Schema.LANES, {})
	for id: int in lanes:
		_lane_lines(lanes[id], points, colours)
	if points.is_empty():
		return
	_overlay_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in points.size():
		_overlay_mesh.surface_set_color(colours[i])
		_overlay_mesh.surface_add_vertex(points[i])
	_overlay_mesh.surface_end()


static func _box_lines(t: Transform3D, half: Vector3, points: PackedVector3Array,
		colours: PackedColorArray) -> void:
	var corners := PackedVector3Array()
	for i in 8:
		corners.append(t * Vector3(half.x * (1 if i & 1 else -1), half.y * (1 if i & 2 else -1),
			half.z * (1 if i & 4 else -1)))
	for i in 8:
		for bit in [1, 2, 4]:
			if not i & bit:
				points.append_array([corners[i], corners[i | bit]])
				colours.append_array([ZONE_COLOUR, ZONE_COLOUR])


static func _lane_lines(lane: LaneData, points: PackedVector3Array,
		colours: PackedColorArray) -> void:
	var colour := LANE_COLOUR if lane.is_lane else PATH_COLOUR
	var lift := Vector3.UP * 0.1
	var previous := lane.point_at(0.0) + lift
	var along := 2.0
	while along < lane.length + 2.0:
		var point := lane.point_at(along) + lift
		points.append_array([previous, point])
		colours.append_array([colour, colour])
		previous = point
		along += 2.0
	var arrow := 5.0
	while arrow < lane.length:
		var tip := lane.point_at(arrow) + lift
		var direction := (tip - lane.point_at(arrow - 0.5) - lift).normalized()
		var side := direction.cross(Vector3.UP).normalized() * 0.5
		for wing in [side, -side]:
			points.append_array([tip, tip - direction * 0.8 + wing])
			colours.append_array([colour, colour])
		arrow += 10.0


func _draw_graph() -> void:
	graph.draw_rect(Rect2(Vector2.ZERO, GRAPH_SIZE), Color(0, 0, 0, 0.35))
	var target := GRAPH_SIZE.y * (1.0 - (1000.0 / 60.0) / GRAPH_TOP_MS)
	graph.draw_line(Vector2(0, target), Vector2(GRAPH_SIZE.x, target), Color(1, 1, 1, 0.25))
	if _frame_ms.size() < 2:
		return
	var line := PackedVector2Array()
	var step := GRAPH_SIZE.x / (GRAPH_FRAMES - 1)
	var start := GRAPH_FRAMES - _frame_ms.size()
	for i in _frame_ms.size():
		var y := GRAPH_SIZE.y * (1.0 - clampf(_frame_ms[i] / GRAPH_TOP_MS, 0.0, 1.0))
		line.append(Vector2((start + i) * step, y))
	graph.draw_polyline(line, Color(0.4, 1.0, 0.5))


func _xr_active() -> bool:
	return XRServer.primary_interface != null and XRServer.primary_interface.is_initialized()


func _build() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	panel.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	panel.offset_left = -16
	panel.offset_right = -16
	panel.offset_top = 16
	add_child(panel)
	var column := VBoxContainer.new()
	panel.add_child(column)
	fps_label = Label.new()
	graph = Control.new()
	graph.custom_minimum_size = GRAPH_SIZE
	graph.draw.connect(_draw_graph)
	performance_label = Label.new()
	speed_label = Label.new()
	speed_label.add_theme_font_size_override(&"font_size", 20)
	position_label = Label.new()
	lane_label = Label.new()
	users_label = Label.new()
	lights_label = Label.new()
	session_label = Label.new()
	tools_label = Label.new()
	tools_label.modulate = Color(1, 1, 1, 0.8)
	var zones := CheckBox.new()
	zones.text = "zones and lanes in 3D"
	zones.button_pressed = overlay_shown
	zones.focus_mode = Control.FOCUS_NONE
	zones.toggled.connect(func(_on: bool) -> void: toggle_overlay())
	var keys := Label.new()
	keys.text = key_hint_text()
	keys.modulate = Color(1, 1, 1, 0.6)
	for node: Control in [fps_label, graph, performance_label, speed_label, position_label,
			lane_label, users_label, lights_label, session_label, tools_label, zones, keys]:
		column.add_child(node)


func _exit_tree() -> void:
	if free_camera:
		free_camera.close()
	if _stepping or get_tree().paused:
		get_tree().paused = false
	_stepping = false
	Engine.time_scale = 1.0
