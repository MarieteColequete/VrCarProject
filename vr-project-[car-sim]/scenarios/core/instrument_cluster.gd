class_name InstrumentCluster
extends Node3D
## The car's instruments, in the cockpit behind the steering wheel, read from the driver's seat
## as in a real car: a speedometer with the speed in figures, a rev counter with the gear, the
## indicator arrows blinking as the indicator does, and the handbrake, headlights, and reverse
## tell-tales. The needles move as real ones do, following their reading on a damped spring
## without overshooting. They are drawn on a small screen ([constant PIXELS]) shown on a panel
## [constant SIZE] metres wide, and drawn again only when what they show changes. Nothing here
## takes part in the simulation.

const PIXELS := Vector2i(640, 224)
const SIZE := Vector2(0.32, 0.112)
## The speedometer's top speed, km/h, and the arc both dials sweep, radians, from their lowest.
const TOP_SPEED := 180.0
const SWEEP := deg_to_rad(240.0)
const START := deg_to_rad(150.0)
## The rev counter's top, revolutions per minute.
const TOP_RPM := 8000.0
## How quickly the needles follow their readings, per second.
const NEEDLE_SPRING := 20.0
## The steps the needles are drawn at: a finer move is not drawn again.
const SPEED_STEP := 0.5
const RPM_STEP := 50.0
const SPEED_CENTRE := Vector2(210.0, 118.0)
const RPM_CENTRE := Vector2(430.0, 118.0)
const RADIUS := 86.0

## What the instruments read: the car's speed, km/h, and its engine's revolutions.
var speed_kmh := 0.0
var rpm := 0.0
## Where the needles are now, following the readings.
var speed_needle := 0.0
var rpm_needle := 0.0
var gear := "N"
var left_on := false
var right_on := false
var handbrake := false
var headlights := false
var reversing := false

var _viewport: SubViewport
var _face: Control
var _shown := []
var _speed_velocity := 0.0
var _rpm_velocity := 0.0


func _init() -> void:
	name = "Instruments"
	_viewport = SubViewport.new()
	_viewport.size = PIXELS
	_viewport.disable_3d = true
	_viewport.transparent_bg = false
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	_face = Control.new()
	_face.size = Vector2(PIXELS)
	_face.draw.connect(_draw_face)
	_viewport.add_child(_face)
	var panel := MeshInstance3D.new()
	panel.name = "Panel"
	var quad := QuadMesh.new()
	quad.size = SIZE
	panel.mesh = quad
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_texture = _viewport.get_texture()
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	panel.material_override = material
	add_child(panel)


## Shows the car's state after a step of [param delta] seconds: the needles move toward
## [param p_speed_kmh] and [param p_rpm], and the rest shows at once. Draws again only when
## something shown changed.
func show_state(delta: float, p_speed_kmh: float, p_rpm: float, p_gear: String, p_left_on: bool,
		p_right_on: bool, p_handbrake: bool, p_headlights: bool, p_reversing: bool) -> void:
	speed_kmh = absf(p_speed_kmh)
	rpm = p_rpm
	gear = p_gear
	left_on = p_left_on
	right_on = p_right_on
	handbrake = p_handbrake
	headlights = p_headlights
	reversing = p_reversing
	var s := Damped.step(speed_needle, _speed_velocity, speed_kmh, NEEDLE_SPRING, delta)
	var r := Damped.step(rpm_needle, _rpm_velocity, rpm, NEEDLE_SPRING, delta)
	speed_needle = s.x
	_speed_velocity = s.y
	rpm_needle = r.x
	_rpm_velocity = r.y
	var now := [roundi(speed_needle / SPEED_STEP), roundi(rpm_needle / RPM_STEP),
		roundi(speed_kmh), gear, left_on, right_on, handbrake, headlights, reversing]
	if now == _shown:
		return
	_shown = now
	_face.queue_redraw()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## The speedometer needle's angle for [param kmh], radians clockwise on the screen from pointing
## right.
static func needle_angle(kmh: float) -> float:
	return START + SWEEP * clampf(kmh / TOP_SPEED, 0.0, 1.0)


## The rev counter needle's angle for [param revs] per minute.
static func rpm_angle(revs: float) -> float:
	return START + SWEEP * clampf(revs / TOP_RPM, 0.0, 1.0)


func _draw_face() -> void:
	var font := ThemeDB.fallback_font
	var ink := Color(0.85, 0.87, 0.9)
	_face.draw_rect(Rect2(Vector2.ZERO, Vector2(PIXELS)), Color(0.04, 0.045, 0.05))
	# The speedometer: a mark every 20 km/h, a figure every 40.
	_dial(SPEED_CENTRE)
	for kmh in range(0, int(TOP_SPEED) + 1, 20):
		_mark(SPEED_CENTRE, needle_angle(kmh), kmh % 40 == 0, ink, str(kmh))
	_needle(SPEED_CENTRE, needle_angle(speed_needle))
	_face.draw_string(font, SPEED_CENTRE + Vector2(-50, 62), "%d" % roundi(speed_kmh),
		HORIZONTAL_ALIGNMENT_CENTER, 100, 40, Color.WHITE)
	_face.draw_string(font, SPEED_CENTRE + Vector2(-40, 84), "km/h", HORIZONTAL_ALIGNMENT_CENTER,
		80, 16, Color(0.7, 0.72, 0.75))
	# The rev counter: a mark every 1000, red past the redline.
	_dial(RPM_CENTRE)
	_face.draw_arc(RPM_CENTRE, RADIUS, rpm_angle(CarDrivetrain.REDLINE_RPM), START + SWEEP, 16,
		Color(0.85, 0.1, 0.08), 6.0, true)
	for thousand in range(0, int(TOP_RPM / 1000.0) + 1):
		var red := thousand * 1000.0 >= CarDrivetrain.REDLINE_RPM
		_mark(RPM_CENTRE, rpm_angle(thousand * 1000.0), true,
			Color(1.0, 0.3, 0.25) if red else ink, str(thousand))
	_needle(RPM_CENTRE, rpm_angle(rpm_needle))
	_face.draw_string(font, RPM_CENTRE + Vector2(-30, 66), gear, HORIZONTAL_ALIGNMENT_CENTER, 60,
		44, Color.WHITE)
	_face.draw_string(font, RPM_CENTRE + Vector2(-50, 84), "x1000 r/min",
		HORIZONTAL_ALIGNMENT_CENTER, 100, 13, Color(0.7, 0.72, 0.75))
	_arrow(Vector2(44, 40), -1.0, left_on)
	_arrow(Vector2(PIXELS.x - 44.0, 40), 1.0, right_on)
	_tell_tale(Vector2(44, 182), "P", Color(1.0, 0.15, 0.1), handbrake)
	_tell_tale(Vector2(PIXELS.x - 44.0, 112), "R", Color(0.95, 0.95, 0.95), reversing)
	_headlamp(Vector2(PIXELS.x - 44.0, 182), headlights)


func _dial(centre: Vector2) -> void:
	_face.draw_arc(centre, RADIUS, START, START + SWEEP, 64, Color(0.35, 0.37, 0.4), 4.0, true)


func _mark(centre: Vector2, a: float, major: bool, colour: Color, label: String) -> void:
	var dir := Vector2(cos(a), sin(a))
	_face.draw_line(centre + dir * (RADIUS - (15.0 if major else 8.0)), centre + dir * RADIUS,
		colour, 4.0 if major else 2.0, true)
	if major:
		_face.draw_string(ThemeDB.fallback_font, centre + dir * (RADIUS - 34.0) + Vector2(-20, 7),
			label, HORIZONTAL_ALIGNMENT_CENTER, 40, 19, colour)


func _needle(centre: Vector2, a: float) -> void:
	_face.draw_line(centre, centre + Vector2(cos(a), sin(a)) * (RADIUS - 6.0),
		Color(1.0, 0.35, 0.1), 5.0, true)
	_face.draw_circle(centre, 8.0, Color(0.8, 0.8, 0.82))


func _arrow(at: Vector2, side: float, on: bool) -> void:
	var colour := Color(0.15, 1.0, 0.3) if on else Color(0.1, 0.2, 0.12)
	var points := PackedVector2Array([at + Vector2(side * 30, 0), at + Vector2(0, -22),
		at + Vector2(0, -10), at + Vector2(-side * 26, -10), at + Vector2(-side * 26, 10),
		at + Vector2(0, 10), at + Vector2(0, 22)])
	_face.draw_colored_polygon(points, colour)


## The headlights' tell-tale: a lamp with its beams.
func _headlamp(at: Vector2, on: bool) -> void:
	var colour := Color(0.2, 0.85, 0.3)
	var shown := colour if on else Color(colour, 0.12)
	_face.draw_arc(at + Vector2(4, 0), 14.0, -PI / 2.0, PI / 2.0, 16, shown, 3.0, true)
	_face.draw_line(at + Vector2(4, -14), at + Vector2(4, 14), shown, 3.0, true)
	for y in [-10.0, 0.0, 10.0]:
		_face.draw_line(at + Vector2(-2, y), at + Vector2(-18, y + 3.0), shown, 3.0, true)


func _tell_tale(at: Vector2, letter: String, colour: Color, on: bool) -> void:
	var shown := colour if on else Color(colour, 0.12)
	_face.draw_arc(at, 20.0, 0.0, TAU, 32, shown, 3.0, true)
	_face.draw_string(ThemeDB.fallback_font, at + Vector2(-20, 9), letter,
		HORIZONTAL_ALIGNMENT_CENTER, 40, 24, shown)
