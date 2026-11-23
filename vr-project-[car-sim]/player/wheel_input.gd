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
## the platform maps as a gamepad has it on a trigger).

const PATH := "user://controls.cfg"
const SECTION := "wheel"

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


## The settings in [param path]; the defaults where it has none.
static func load_from(path := PATH) -> WheelInput:
	var out := WheelInput.new()
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return out
	for key in ["enabled", "device", "name", "steer_axis", "rotation", "throttle_axis",
			"throttle_rest", "throttle_pressed", "brake_axis", "brake_rest", "brake_pressed"]:
		out.set(key, config.get_value(SECTION, key, out.get(key)))
	return out


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
	return _pedal(throttle_axis, throttle_rest, throttle_pressed)


## The brake pedal, 0 to 1; 0 with no wheel or no brake axis set.
func brake() -> float:
	return _pedal(brake_axis, brake_rest, brake_pressed)


func _pedal(axis: int, rest: float, pressed: float) -> float:
	var id := joypad()
	if id < 0 or axis < 0:
		return 0.0
	return pedal(Input.get_joy_axis(id, axis), rest, pressed)
