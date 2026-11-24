class_name CarTablet
extends Node3D
## A tablet held out from the dashboard on an arm, right of the instruments and turned to the
## driver, running a GPS:
## the roads round the car ([GpsMap]), heading up, the car fixed low in the middle and the map
## turning and sliding under it, zoomed out as it speeds up; the way the scenario wants it to go,
## from where the car is on it to the goal, and the goal's pin, kept at the screen's edge when it
## is off it; and across the top the step's title and instruction (the scenario's title and its
## briefing's first sentence when it has no steps) with the metres left to go. It is drawn on a
## small screen ([constant PIXELS]) at most [constant RATE] times a second, and only when what it
## shows changed. Nothing here takes part in the simulation.

## The screen and the tablet's size, metres.
const PIXELS := Vector2i(768, 512)
const SIZE := Vector2(0.24, 0.16)
const BEZEL := 0.012
const DEPTH := 0.012
## The arm's thickness, metres.
const ARM_RADIUS := 0.011
## The most times a second the screen is drawn.
const RATE := 15.0
## Where the car sits on the screen, and how many pixels to the metre the map is drawn at, at a
## standstill and from [constant ZOOM_SPEED] metres per second up, eased over [constant ZOOM_TIME]
## seconds.
const ANCHOR := Vector2(384.0, 400.0)
const NEAR_SCALE := 4.5
const FAR_SCALE := 2.2
const ZOOM_SPEED := 20.0
const ZOOM_TIME := 1.5
## The bar across the top, pixels.
const HEADER := 116.0
const GROUND := Color(0.13, 0.15, 0.13)
const ROAD := Color(0.42, 0.43, 0.45)
const LINE := Color(0.78, 0.78, 0.74)
const WAY := Color(0.2, 0.55, 1.0)
const GOAL := Color(1.0, 0.3, 0.25)
const CAR := Color(1.0, 1.0, 1.0)
const BAR := Color(0.06, 0.07, 0.09, 0.92)
const TEXT := Color(0.95, 0.96, 0.98)
const DIM_TEXT := Color(0.7, 0.74, 0.8)

## What the GPS shows: the map, null before a scenario loads.
var map: GpsMap
## The current step's index, -1 with none; and what the bar says.
var step := -1
var title := ""
var instruction := ""
## The car on the ground (x and z), the way it faces there, and the zoom, pixels to the metre.
var car := Vector2.ZERO
var forward := Vector2(0.0, -1.0)
var scale_now := NEAR_SCALE
## The metres left to the goal, along the way or straight to it; -1 with no goal.
var left := -1.0
## How many times the screen has been drawn.
var draws := 0

var screen: MeshInstance3D
var arm: MeshInstance3D
var _viewport: SubViewport
var _face: Control
var _roads: ArrayMesh
var _since := INF
var _shown := []


func _init() -> void:
	name = "Tablet"
	_viewport = SubViewport.new()
	_viewport.size = PIXELS
	_viewport.disable_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	_face = Control.new()
	_face.size = Vector2(PIXELS)
	_face.draw.connect(_draw_face)
	_viewport.add_child(_face)
	var case := StandardMaterial3D.new()
	case.albedo_color = Color(0.05, 0.05, 0.055)
	case.roughness = 0.6
	var body := MeshInstance3D.new()
	body.name = "Body"
	var box := BoxMesh.new()
	box.size = Vector3(SIZE.x + BEZEL * 2.0, SIZE.y + BEZEL * 2.0, DEPTH)
	body.mesh = box
	body.material_override = case
	body.position.z = -DEPTH / 2.0
	add_child(body)
	# The arm that holds it out from the dash, with a ball joint at each end.
	arm = MeshInstance3D.new()
	arm.name = "Arm"
	var rod := CylinderMesh.new()
	rod.top_radius = ARM_RADIUS
	rod.bottom_radius = ARM_RADIUS
	rod.height = 1.0
	arm.mesh = rod
	arm.material_override = case
	add_child(arm)
	for joint_name in ["Grip", "Mount"]:
		var joint := MeshInstance3D.new()
		joint.name = joint_name
		var ball := SphereMesh.new()
		ball.radius = ARM_RADIUS * 1.8
		ball.height = ARM_RADIUS * 3.6
		joint.mesh = ball
		joint.material_override = case
		add_child(joint)
	screen = MeshInstance3D.new()
	screen.name = "Screen"
	var quad := QuadMesh.new()
	quad.size = SIZE
	screen.mesh = quad
	var glass := StandardMaterial3D.new()
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.albedo_texture = _viewport.get_texture()
	glass.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	screen.material_override = glass
	screen.position.z = 0.0005
	add_child(screen)


## Holds the tablet out on its arm from [param mount] on the dash to [param centre], both in its
## parent's space, its screen turned to [param eye].
func place(mount: Vector3, centre: Vector3, eye: Vector3) -> void:
	transform = Transform3D(Basis.looking_at(centre - eye, Vector3.UP), centre)
	var grip := Vector3(0.0, 0.0, -DEPTH - ARM_RADIUS * 1.8)
	var base := transform.affine_inverse() * mount
	var along := base - grip
	arm.transform = Transform3D(_pointing(along.normalized()).scaled_local(
		Vector3(1.0, along.length(), 1.0)), (grip + base) / 2.0)
	(get_node("Grip") as Node3D).position = grip
	(get_node("Mount") as Node3D).position = base


## A basis whose y axis points along [param direction].
static func _pointing(direction: Vector3) -> Basis:
	var side := direction.cross(Vector3.FORWARD)
	if side.length_squared() < 1e-6:
		side = direction.cross(Vector3.RIGHT)
	side = side.normalized()
	return Basis(side, direction, side.cross(direction))


## Shows [param p_map], the scenario's, from its start.
func load_map(p_map: GpsMap) -> void:
	map = p_map
	_roads = _mesh(map)
	_shown = []


## Shows step [param index] (-1 for none) with [param p_title] and [param p_instruction] across
## the top.
func show_step(index: int, p_title: String, p_instruction: String) -> void:
	step = index
	title = p_title
	instruction = p_instruction
	_shown = []


## Follows the car for a frame of [param delta] seconds: at [param position], facing
## [param p_forward], at [param speed] metres per second.
func follow(delta: float, position_now: Vector3, p_forward: Vector3, speed: float) -> void:
	car = Vector2(position_now.x, position_now.z)
	var flat := Vector2(p_forward.x, p_forward.z)
	if flat.length_squared() > 1e-4:
		forward = flat.normalized()
	var wanted := lerpf(NEAR_SCALE, FAR_SCALE, clampf(absf(speed) / ZOOM_SPEED, 0.0, 1.0))
	scale_now = Damped.follow(scale_now, wanted, delta, ZOOM_TIME)
	left = _left()
	_since += delta
	if _since < 1.0 / RATE:
		return
	var now := [roundi(car.x * 10.0), roundi(car.y * 10.0), roundi(forward.angle() * 200.0),
		roundi(scale_now * 20.0), roundi(left), step, title, instruction]
	if now == _shown:
		return
	_shown = now
	_since = 0.0
	draws += 1
	_face.queue_redraw()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## The screen's transform from the ground, as last drawn.
func view() -> Transform2D:
	return GpsMap.heading_up(car, forward, scale_now, ANCHOR)


func _left() -> float:
	if map == null:
		return -1.0
	var way := map.route_for(step)
	if way.size() >= 2:
		return GpsMap.along(way, car).left
	var goal := map.goal_for(step)
	return car.distance_to(goal.centre) if not goal.is_empty() else -1.0


static func _mesh(p_map: GpsMap) -> ArrayMesh:
	var points := PackedVector2Array()
	var colours := PackedColorArray()
	points.append_array(p_map.roads)
	points.append_array(p_map.islands)
	colours.resize(points.size())
	for i in points.size():
		colours[i] = ROAD if i < p_map.roads.size() else GROUND
	if points.is_empty():
		return null
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points
	arrays[Mesh.ARRAY_COLOR] = colours
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _draw_face() -> void:
	var rect := Rect2(Vector2.ZERO, Vector2(PIXELS))
	_face.draw_rect(rect, GROUND)
	if map:
		var at := view()
		_face.draw_set_transform_matrix(at)
		if _roads:
			_face.draw_mesh(_roads, null)
		var thin := 1.5 / scale_now
		for line in map.lines:
			_face.draw_polyline(line, LINE, thin)
		var way := map.route_for(step)
		if way.size() >= 2:
			var near := GpsMap.along(way, car)
			var rest := PackedVector2Array([near.point])
			rest.append_array(way.slice(near.index + 1))
			_face.draw_polyline(rest, WAY, 9.0 / scale_now)
		_face.draw_set_transform_matrix(Transform2D.IDENTITY)
		var goal := map.goal_for(step)
		if not goal.is_empty():
			var inner := rect.grow_individual(-24.0, -HEADER - 24.0, -24.0, -24.0)
			var pin: Vector2 = at * goal.centre
			pin = pin.clamp(inner.position, inner.end)
			_face.draw_circle(pin, 13.0, GOAL)
			_face.draw_circle(pin, 5.0, Color.WHITE)
	# The car, an arrow pointing up.
	_face.draw_colored_polygon(PackedVector2Array([ANCHOR + Vector2(0, -20), ANCHOR + Vector2(13, 14),
		ANCHOR + Vector2(0, 7), ANCHOR + Vector2(-13, 14)]), CAR)
	_draw_bar()


func _draw_bar() -> void:
	var font := ThemeDB.fallback_font
	_face.draw_rect(Rect2(0.0, 0.0, PIXELS.x, HEADER), BAR)
	var distance := ""
	if left >= 0.0:
		distance = "%d m" % roundi(left) if left < 1000.0 else "%.1f km" % (left / 1000.0)
	var right := 20.0
	if distance != "":
		var line := TextLine.new()
		line.add_string(distance, font, 44)
		right = line.get_line_width() + 36.0
		line.draw(_face.get_canvas_item(), Vector2(PIXELS.x - line.get_line_width() - 20.0, 14.0),
			TEXT)
	var room := PIXELS.x - 20.0 - right
	var head := TextLine.new()
	head.add_string(title, font, 34)
	head.width = room
	head.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	head.draw(_face.get_canvas_item(), Vector2(20.0, 12.0), TEXT)
	var body := TextParagraph.new()
	body.add_string(instruction, font, 24)
	body.width = PIXELS.x - 40.0
	body.max_lines_visible = 2
	body.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	body.draw(_face.get_canvas_item(), Vector2(20.0, 60.0), DIM_TEXT)
