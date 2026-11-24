class_name InstrumentCluster
extends Node3D
## The car's instruments, in the cockpit behind the steering wheel, read from the driver's seat
## as in a real car: a speedometer with the speed in figures, a rev counter with the gear, the
## indicator arrows blinking as the indicator does, the handbrake, headlights, and reverse
## tell-tales, a fuel gauge and a coolant gauge at the panel's ends, and the warning lights (engine,
## oil, battery, ABS, stability control, low fuel) from a [DashState]. The needles move as real
## ones do, following their reading on a damped spring without overshooting. They are drawn on a
## small screen ([constant PIXELS]) shown on the model's own gauge face ([method mount]), or on a
## panel [constant SIZE] metres wide when the model has none, and drawn again only when what they
## show changes. Nothing here takes part in the simulation.

## The screen, the proportions of the model's gauge face (0.46 m by 0.14 m).
const PIXELS := Vector2i(800, 245)
const SIZE := Vector2(0.46, 0.141)
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
const SPEED_CENTRE := Vector2(260.0, 124.0)
const RPM_CENTRE := Vector2(540.0, 124.0)
const RADIUS := 92.0
## The small gauges at the ends: fuel on the left, coolant on the right, each sweeping
## [constant SMALL_SWEEP] radians about its centre, and the coolant's span, degrees Celsius.
const FUEL_CENTRE := Vector2(75.0, 132.0)
const COOLANT_CENTRE := Vector2(725.0, 132.0)
const SMALL_RADIUS := 46.0
const SMALL_SWEEP := deg_to_rad(100.0)
const COOLANT_LOW := 50.0
const COOLANT_HIGH := 130.0

## The revolutions past which the rev counter is red; the car sets its engine's.
var redline := 7400.0
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
## The warning lights and the small gauges; the car steps it.
var dash := DashState.new()

## The face the instruments are drawn on, or null while they are on their own panel.
var mounted: MeshInstance3D

var _panel: MeshInstance3D
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
	_panel = panel


## Draws the instruments on [param face], a face cut out of the car's model with UVs across it
## ([member PlayerCarModel.cluster_face]), instead of on the cluster's own panel.
func mount(face: MeshInstance3D) -> void:
	face.material_override = _panel.material_override
	_panel.visible = false
	mounted = face


## Shows the car's state after a step of [param delta] seconds: the needles move toward
## [param p_speed_kmh] and [param p_rpm], and the rest shows at once. Draws again only when
## something shown changed.
## The warning lights and small gauges show [member dash] as the car last stepped it.
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
		roundi(speed_kmh), gear, left_on, right_on, handbrake, headlights, reversing,
		dash.engine_light, dash.oil_light, dash.battery_light, dash.abs_light, dash.esc_light,
		dash.fuel_light, roundi(dash.fuel * 200.0), roundi(dash.coolant)]
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


## A small gauge's needle angle for [param share] (0 to 1) of its sweep, from lower left to
## lower right over the top.
static func small_angle(share: float) -> float:
	return -PI / 2.0 - SMALL_SWEEP / 2.0 + SMALL_SWEEP * clampf(share, 0.0, 1.0)


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
	_face.draw_arc(RPM_CENTRE, RADIUS, rpm_angle(redline), START + SWEEP, 16,
		Color(0.85, 0.1, 0.08), 6.0, true)
	for thousand in range(0, int(TOP_RPM / 1000.0) + 1):
		var past_redline := thousand * 1000.0 >= redline
		_mark(RPM_CENTRE, rpm_angle(thousand * 1000.0), true,
			Color(1.0, 0.3, 0.25) if past_redline else ink, str(thousand))
	_needle(RPM_CENTRE, rpm_angle(rpm_needle))
	_face.draw_string(font, RPM_CENTRE + Vector2(-30, 66), gear, HORIZONTAL_ALIGNMENT_CENTER, 60,
		44, Color.WHITE)
	_face.draw_string(font, RPM_CENTRE + Vector2(-50, 84), "x1000 r/min",
		HORIZONTAL_ALIGNMENT_CENTER, 100, 13, Color(0.7, 0.72, 0.75))
	# The ends: the indicator arrows on top, the fuel and coolant gauges, the warning lights below.
	_arrow(Vector2(75, 36), -1.0, left_on)
	_arrow(Vector2(PIXELS.x - 75.0, 36), 1.0, right_on)
	_small_gauge(FUEL_CENTRE, dash.fuel, "E", "F", "FUEL", dash.fuel < DashState.FUEL_LOW)
	_small_gauge(COOLANT_CENTRE, inverse_lerp(COOLANT_LOW, COOLANT_HIGH, dash.coolant), "C", "H",
		"TEMP", dash.coolant > 115.0)
	var red := Color(1.0, 0.18, 0.12)
	var amber := Color(1.0, 0.62, 0.05)
	_lamp(Vector2(30, 214), "ENG", amber, dash.engine_light)
	_lamp(Vector2(75, 214), "OIL", red, dash.oil_light)
	_lamp(Vector2(120, 214), "BAT", red, dash.battery_light)
	_lamp(Vector2(PIXELS.x - 120.0, 214), "ABS", amber, dash.abs_light)
	_lamp(Vector2(PIXELS.x - 75.0, 214), "ESC", amber, dash.esc_light)
	_lamp(Vector2(PIXELS.x - 30.0, 214), "FUEL", amber, dash.fuel_light)
	# Between the dials: the handbrake, the headlights, reverse.
	_tell_tale(Vector2(PIXELS.x / 2.0, 52), "P", red, handbrake)
	_headlamp(Vector2(PIXELS.x / 2.0 + 6.0, 124), headlights)
	_tell_tale(Vector2(PIXELS.x / 2.0, 196), "R", Color(0.95, 0.95, 0.95), reversing)


## A small gauge at [param centre] reading [param share] of its sweep, [param low] and [param high]
## at its ends and [param title] under it; its far end red, the needle red when [param warn].
func _small_gauge(centre: Vector2, share: float, low: String, high: String, title: String,
		warn: bool) -> void:
	var font := ThemeDB.fallback_font
	var ink := Color(0.85, 0.87, 0.9)
	var from := small_angle(0.0)
	_face.draw_arc(centre, SMALL_RADIUS, from, from + SMALL_SWEEP, 32, Color(0.35, 0.37, 0.4),
		3.0, true)
	for k in 5:
		var mark := small_angle(k / 4.0)
		var dir := Vector2(cos(mark), sin(mark))
		_face.draw_line(centre + dir * (SMALL_RADIUS - 8.0), centre + dir * SMALL_RADIUS, ink,
			2.0, true)
	for end in [[low, 0.0], [high, 1.0]]:
		var at_end := small_angle(end[1])
		var at := centre + Vector2(cos(at_end), sin(at_end)) * (SMALL_RADIUS + 12.0)
		_face.draw_string(font, at + Vector2(-10, 6), end[0], HORIZONTAL_ALIGNMENT_CENTER, 20,
			16, ink)
	var a := small_angle(share)
	_face.draw_line(centre, centre + Vector2(cos(a), sin(a)) * (SMALL_RADIUS - 4.0),
		Color(1.0, 0.2, 0.1) if warn else Color(1.0, 0.35, 0.1), 4.0, true)
	_face.draw_circle(centre, 6.0, Color(0.8, 0.8, 0.82))
	_face.draw_string(font, centre + Vector2(-30, 26), title, HORIZONTAL_ALIGNMENT_CENTER, 60, 14,
		Color(0.7, 0.72, 0.75))


## A warning light at [param at]: [param label] in [param colour] in a rounded frame, lit when
## [param on], a dim ghost when not.
func _lamp(at: Vector2, label: String, colour: Color, on: bool) -> void:
	var shown := colour if on else Color(colour, 0.12)
	_face.draw_rect(Rect2(at - Vector2(20, 13), Vector2(40, 26)), shown, false, 2.0, true)
	_face.draw_string(ThemeDB.fallback_font, at + Vector2(-20, 6), label,
		HORIZONTAL_ALIGNMENT_CENTER, 40, 13 if label.length() > 3 else 15, shown)


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
