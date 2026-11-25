class_name WheelInput
extends RefCounted
## A steering wheel and its pedals. The platform presents most wheels as a gamepad, so their
## buttons (the paddles as the shoulders, A, B, X, Y, the D-pad, Start and View, the stick buttons)
## already drive the same actions as a gamepad's; what a wheel adds is read here: the rim, turned
## 1:1 into the car's own steering wheel with no rate limit, and pedals on axes of their own,
## calibrated for where each rests and how far it travels.
##
## Set in [constant PATH], section [constant SECTION]: [code]enabled[/code] ("auto", the first
## joypad whose name holds [code]name[/code]; true; false), [code]device[/code] (a joypad index,
## -1 to find it by name), [code]name[/code] ("wheel"), [code]steer_axis[/code] (0),
## [code]rotation[/code] (the rim's turn lock to lock in degrees, as the wheel's own software sets
## it; 900, the car's own wheel and most wheels' default), and per pedal
## [code]throttle_axis[/code], [code]throttle_rest[/code], [code]throttle_pressed[/code] and the
## same for [code]brake[/code] (an axis of -1 leaves that pedal to the input actions, as a wheel
## the platform maps as a gamepad has it on a trigger), and [code]shift_up_button[/code] and
## [code]shift_down_button[/code] (the paddles' joypad buttons, -1 leaving them to the gamepad's
## shoulders), and [code]shifter_d_button[/code], [code]shifter_p_button[/code] and
## [code]shifter_r_button[/code] (the shifter positions that put the automatic in D, P and R;
## any other position is N; -1 leaves a position unused).
##
## A wheel the platform does not map as a gamepad needs its pedals, paddles and shifter set;
## [constant PROFILES] sets them for the wheels known to need it, for each setting the file leaves
## out. Its paddles then move the lever as a gamepad's shoulders do ([method paddle]), and its gear
## shifter puts the lever where the shifter is ([method shifter_change]).

const PATH := "user://controls.cfg"
const SECTION := "wheel"
## Pedal, paddle and shifter settings of wheels Godot sees as unknown joypads, keyed by
## [code]"vendor_id:product_id"[/code] as [method Input.get_joy_info] gives them.
const PROFILES := {
	# Logitech G29 in its native mode, which G HUB switches it to: a pedal per axis, each resting
	# at 1 and fully pressed at -1 (the clutch, on axis 3, is not read); the right paddle is
	# button 4 and the left button 5.
	"1133:49743": {throttle_axis = 1, throttle_rest = 1.0, throttle_pressed = -1.0,
		brake_axis = 2, brake_rest = 1.0, brake_pressed = -1.0,
		shift_up_button = 4, shift_down_button = 5,
		# Its shifter's gears are buttons 12 (first) to 17 (sixth) and 18 (reverse), but Godot
		# also gives its D-pad as buttons 11 to 14 (up, down, left, right), so first to third
		# cannot be told from the D-pad, and the D-pad's right can read held from the wheel's first
		# report until it is pressed. The lever positions keep clear of them: fifth gear (16) is D,
		# fourth (15) P, and reverse (18) R.
		shifter_d_button = 16, shifter_p_button = 15, shifter_r_button = 18},
	# Logitech G29 in its PS3 compatibility mode, with no G HUB: both pedals on axis 1, the
	# throttle towards -1 and the brake towards 1.
	"1133:49812": {throttle_axis = 1, throttle_rest = 0.0, throttle_pressed = -1.0,
		brake_axis = 1, brake_rest = 0.0, brake_pressed = 1.0},
}

var enabled: Variant = "auto"
var device := -1
var name := "wheel"
var steer_axis := 0
## The rim's turn lock to lock, degrees.
var rotation := rad_to_deg(Steering.WHEEL_TURN) * 2.0
var throttle_axis := -1
var throttle_rest := -1.0
var throttle_pressed := 1.0
var brake_axis := -1
var brake_rest := -1.0
var brake_pressed := 1.0
var shift_up_button := -1
var shift_down_button := -1
var shifter_d_button := -1
var shifter_p_button := -1
var shifter_r_button := -1
## The settings the file set, which a profile leaves as they are.
var configured := PackedStringArray()
## The pedal axes that have reported a value. Until a wheel's first report Godot gives its axes as
## exactly 0, which on a pedal resting elsewhere would read as part pressed, so such a pedal reads
## released until its axis has moved.
var _reported := {}
## The shifter position last seen ([method shifter_change]); empty before the first look.
var _shifter := ""


## The settings in [param path]; the defaults where it has none.
static func load_from(path := PATH) -> WheelInput:
	var out := WheelInput.new()
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return out
	for key in ["enabled", "device", "name", "steer_axis", "rotation", "throttle_axis",
			"throttle_rest", "throttle_pressed", "brake_axis", "brake_rest", "brake_pressed",
			"shift_up_button", "shift_down_button", "shifter_d_button", "shifter_p_button",
			"shifter_r_button"]:
		if config.has_section_key(SECTION, key):
			out.set(key, config.get_value(SECTION, key))
			out.configured.append(key)
	return out


## One pedal's axis, rest, and fully pressed value, for [param pedal_name] "throttle" or "brake",
## on the joypad [param info] describes ([method Input.get_joy_info]): the file's settings, else
## the joypad's profile in [constant PROFILES], else the defaults.
func pedal_settings(pedal_name: String, info: Dictionary) -> Vector3:
	return Vector3(setting("%s_axis" % pedal_name, info), setting("%s_rest" % pedal_name, info),
		setting("%s_pressed" % pedal_name, info))


## The setting [param key] for the joypad [param info] describes: the file's, else the joypad's
## profile in [constant PROFILES], else the default.
func setting(key: String, info: Dictionary) -> Variant:
	if configured.has(key):
		return get(key)
	var profile: Dictionary = PROFILES.get(
		"%s:%s" % [info.get("vendor_id", ""), info.get("product_id", "")], {})
	return profile.get(key, get(key))


## The lever move a paddle of the wheel asks for, pressed or let go, in [param event]: 1 the up
## paddle, -1 the down paddle, 0 any other event.
func paddle(event: InputEvent) -> int:
	if not event is InputEventJoypadButton:
		return 0
	var id := joypad()
	if id < 0 or event.device != id:
		return 0
	return paddle_of(event.button_index, Input.get_joy_info(id))


## The lever move of joypad button [param button] on the joypad [param info] describes: 1 for its
## up paddle, -1 for its down paddle, 0 for any other button.
func paddle_of(button: int, info: Dictionary) -> int:
	if button == int(setting("shift_up_button", info)):
		return 1
	if button == int(setting("shift_down_button", info)):
		return -1
	return 0


## The automatic's lever position the shifter has moved to since the last call, by letter (P, R,
## N, D), or empty when it has not moved or the wheel has no shifter set. Called once a physics
## step. The first look puts the lever where the shifter is only when the shifter is in one of its
## set positions, so a shifter resting in neutral, or none at all, leaves the car as it starts.
func shifter_change() -> String:
	var id := joypad()
	if id < 0:
		return ""
	return shifter_step(shifter_position(func(button: int) -> bool:
		return Input.is_joy_button_pressed(id, button), Input.get_joy_info(id)))


## [method shifter_change] for the shifter now at [param now] ([method shifter_position]).
func shifter_step(now: String) -> String:
	var first := _shifter.is_empty()
	if now == _shifter or now.is_empty():
		return ""
	_shifter = now
	return "" if first and now == "N" else now


## The lever position the shifter is in, by letter: D, P or R when the button of that position is
## held ([param pressed] takes a button and tells whether it is), else N; empty when the joypad
## [param info] describes has no shifter set.
func shifter_position(pressed: Callable, info: Dictionary) -> String:
	var any_set := false
	for position in ["D", "P", "R"]:
		var button := int(setting("shifter_%s_button" % position.to_lower(), info))
		if button < 0:
			continue
		any_set = true
		if pressed.call(button):
			return position
	return "N" if any_set else ""


## The car's steering, -1 (full right) to 1 (full left), for a rim at [param raw] (-1 full left
## to 1 full right, as an axis gives it) turning [param degrees] lock to lock: the car's wheel
## turns as far as the rim, up to its own lock ([constant Steering.WHEEL_TURN]).
static func turn(raw: float, degrees: float) -> float:
	var angle := deg_to_rad(raw * degrees * 0.5)
	return clampf(-angle / Steering.WHEEL_TURN, -1.0, 1.0)


## How far a pedal at [param raw] is pressed, 0 to 1, for one resting at [param rest] and fully
## pressed at [param pressed]: either way round, so an inverted pedal calibrates too.
static func pedal(raw: float, rest: float, pressed: float) -> float:
	if is_equal_approx(rest, pressed):
		return 0.0
	return clampf((raw - rest) / (pressed - rest), 0.0, 1.0)


## The joypad the wheel is, or -1 when it is off or not connected.
func joypad() -> int:
	if enabled is bool and not enabled:
		return -1
	var connected := Input.get_connected_joypads()
	if device >= 0:
		return device if connected.has(device) else -1
	if enabled is bool or str(enabled) == "auto":
		for id in connected:
			if Input.get_joy_name(id).to_lower().contains(name.to_lower()):
				return id
	return -1


## Whether a wheel drives the car.
func active() -> bool:
	return joypad() >= 0


## The car's steering from the rim; 0 with no wheel.
func steer() -> float:
	var id := joypad()
	return turn(Input.get_joy_axis(id, steer_axis), rotation) if id >= 0 else 0.0


## The throttle pedal, 0 to 1; 0 with no wheel or no throttle axis set.
func throttle() -> float:
	return _pedal("throttle")


## The brake pedal, 0 to 1; 0 with no wheel or no brake axis set.
func brake() -> float:
	return _pedal("brake")


func _pedal(pedal_name: String) -> float:
	var id := joypad()
	if id < 0:
		return 0.0
	var settings := pedal_settings(pedal_name, Input.get_joy_info(id))
	if settings.x < 0.0:
		return 0.0
	var axis := int(settings.x)
	var raw := Input.get_joy_axis(id, axis)
	if raw != 0.0:
		_reported[axis] = true
	return pedal_reading(raw, settings.y, settings.z, _reported.has(axis))


## [method pedal] for a pedal whose axis has [param reported] a value yet: before that, a pedal
## resting anywhere but 0 reads released, as its axis's 0 is no report rather than a position.
static func pedal_reading(raw: float, rest: float, pressed: float, reported: bool) -> float:
	if not reported and not is_zero_approx(rest):
		return 0.0
	return pedal(raw, rest, pressed)
