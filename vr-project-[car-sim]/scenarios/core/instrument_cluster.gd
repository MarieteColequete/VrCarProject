class_name InstrumentCluster
extends Node3D
## The car's instruments, in the cockpit behind the steering wheel, read from the driver's seat
## as in a real car: a speedometer with a needle and the speed in figures, the indicator arrows
## blinking as the indicator does, and the handbrake, headlights, and reverse tell-tales. They are
## drawn on a small screen ([constant PIXELS]) shown on a panel [constant SIZE] metres wide, and
## drawn again only when what they show changes. Nothing here takes part in the simulation.

const PIXELS := Vector2i(512, 224)
const SIZE := Vector2(0.26, 0.114)
## The speedometer's top speed, km/h, and the arc it sweeps, radians, from its lowest.
const TOP_SPEED := 180.0
const SWEEP := deg_to_rad(240.0)
const START := deg_to_rad(150.0)

var speed_kmh := 0.0
var left_on := false
var right_on := false
var handbrake := false
var headlights := false
var reversing := false

var _viewport: SubViewport
var _face: Control
var _shown := []


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


## Shows the car's state; draws again only when something shown changed.
func show_state(p_speed_kmh: float, p_left_on: bool, p_right_on: bool, p_handbrake: bool,
		p_headlights: bool, p_reversing: bool) -> void:
	speed_kmh = absf(p_speed_kmh)
	left_on = p_left_on
	right_on = p_right_on
	handbrake = p_handbrake
	headlights = p_headlights
	reversing = p_reversing
	var now := [roundi(speed_kmh), left_on, right_on, handbrake, headlights, reversing]
	if now == _shown:
		return
	_shown = now
	_face.queue_redraw()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


## The needle's angle for [param kmh], radians clockwise on the screen from pointing right.
static func needle_angle(kmh: float) -> float:
	return START + SWEEP * clampf(kmh / TOP_SPEED, 0.0, 1.0)


func _draw_face() -> void:
	var font := ThemeDB.fallback_font
	_face.draw_rect(Rect2(Vector2.ZERO, Vector2(PIXELS)), Color(0.04, 0.045, 0.05))
	var centre := Vector2(PIXELS.x / 2.0, 128.0)
	var r := 92.0
	_face.draw_arc(centre, r, START, START + SWEEP, 64, Color(0.35, 0.37, 0.4), 4.0, true)
	for kmh in range(0, int(TOP_SPEED) + 1, 20):
		var a := needle_angle(kmh)
		var dir := Vector2(cos(a), sin(a))
		var major := kmh % 40 == 0
		_face.draw_line(centre + dir * (r - (16.0 if major else 9.0)), centre + dir * r,
			Color(0.85, 0.87, 0.9), 4.0 if major else 2.0, true)
		if major:
			_face.draw_string(font, centre + dir * (r - 38.0) + Vector2(-20, 8), str(kmh),
				HORIZONTAL_ALIGNMENT_CENTER, 40, 22, Color(0.85, 0.87, 0.9))
	var a := needle_angle(speed_kmh)
	_face.draw_line(centre, centre + Vector2(cos(a), sin(a)) * (r - 6.0), Color(1.0, 0.35, 0.1),
		5.0, true)
	_face.draw_circle(centre, 8.0, Color(0.8, 0.8, 0.82))
	_face.draw_string(font, centre + Vector2(-50, 66), "%d" % roundi(speed_kmh),
		HORIZONTAL_ALIGNMENT_CENTER, 100, 44, Color.WHITE)
	_face.draw_string(font, centre + Vector2(-40, 90), "km/h", HORIZONTAL_ALIGNMENT_CENTER, 80, 18,
		Color(0.7, 0.72, 0.75))
	_arrow(Vector2(62, 40), -1.0, left_on)
	_arrow(Vector2(PIXELS.x - 62.0, 40), 1.0, right_on)
	_tell_tale(Vector2(70, 180), "P", Color(1.0, 0.15, 0.1), handbrake)
	_headlamp(Vector2(PIXELS.x - 70.0, 180), headlights)
	_tell_tale(Vector2(PIXELS.x - 70.0, 112), "R", Color(0.95, 0.95, 0.95), reversing)


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
