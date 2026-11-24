class_name DriverInput
extends RefCounted
## The car controls, read from the input actions in project.godot. Keyboard, gamepad, and a wheel
## the platform presents as a gamepad are events on the same actions, so a car script reads these
## helpers and never a device; a wheel's rim and pedals also come through [WheelInput]. Keys give
## full values; triggers and sticks give analog values past the action's deadzone.

const THROTTLE := &"throttle"
const BRAKE := &"brake"
const STEER_LEFT := &"steer_left"
const STEER_RIGHT := &"steer_right"
const HANDBRAKE := &"handbrake"
const INDICATOR_LEFT := &"indicator_left"
const INDICATOR_RIGHT := &"indicator_right"
const HEADLIGHTS := &"toggle_headlights"
## The gear lever, a notch at a time: the automatic's D, N, R from top to bottom, the manual's
## gears. On a gamepad, shift_down held [constant PARK_HOLD] seconds is the park button: a gesture
## on whatever button shift_down is bound to, the one place a car reads a device
## ([method is_pad_shift_down]), as a pad has no button left for park of its own.
const SHIFT_UP := &"shift_up"
const SHIFT_DOWN := &"shift_down"
## The automatic's park button.
const PARK := &"park"
## Seconds a gamepad's shift_down is held to park, a tap still moving the lever.
const PARK_HOLD := 0.5
## The key: held to turn the engine over until it catches, pressed to switch it off.
const IGNITION := &"ignition"
## The mirror tilt controls: the arrow keys, and the D-pad, whose other jobs (the indicators,
## restart, next) wait while a mirror is picked ([method taken_by_mirror]).
const MIRROR_TILT: Array[StringName] = [&"mirror_tilt_left", &"mirror_tilt_right",
	&"mirror_tilt_up", &"mirror_tilt_down"]

## Every action a car reads, for checks that the bindings exist.
const CAR_ACTIONS: Array[StringName] = [
	THROTTLE, BRAKE, STEER_LEFT, STEER_RIGHT, HANDBRAKE, INDICATOR_LEFT, INDICATOR_RIGHT,
	HEADLIGHTS, SHIFT_UP, SHIFT_DOWN, PARK, IGNITION]


## The steering wheel and pedals ([WheelInput]), read once from its settings; replaced by tests.
static var wheel: WheelInput:
	get:
		if wheel == null:
			wheel = WheelInput.load_from()
		return wheel


## Accelerator, 0 to 1: the throttle action or a wheel's pedal, whichever is further down.
static func throttle() -> float:
	return maxf(Input.get_action_strength(THROTTLE), wheel.throttle())


## Brake, 0 to 1: the brake action or a wheel's pedal, whichever is further down.
static func brake() -> float:
	return maxf(Input.get_action_strength(BRAKE), wheel.brake())


## Steering, -1 (full right) to 1 (full left), matching a positive rotation about Y.
static func steer() -> float:
	return Input.get_axis(STEER_RIGHT, STEER_LEFT)


static func handbrake() -> bool:
	return Input.is_action_pressed(HANDBRAKE)


## Whether the key is held in the start position.
static func ignition() -> bool:
	return Input.is_action_pressed(IGNITION)


## Whether an input event switches the headlights on or off.
static func headlights_pressed(event: InputEvent) -> bool:
	return event.is_action_pressed(HEADLIGHTS)


## The indicator an input event switches, as a [enum VehicleProbe.Indicator]; OFF when it is not
## an indicator press.
static func indicator_pressed(event: InputEvent) -> VehicleProbe.Indicator:
	if event.is_action_pressed(INDICATOR_LEFT):
		return VehicleProbe.Indicator.LEFT
	if event.is_action_pressed(INDICATOR_RIGHT):
		return VehicleProbe.Indicator.RIGHT
	return VehicleProbe.Indicator.OFF


## Whether [param event] tilts a mirror rather than doing its other job, with a mirror picked
## when [param picking]: the D-pad tilts the mirror while one is picked.
static func taken_by_mirror(event: InputEvent, picking: bool) -> bool:
	if not picking:
		return false
	for action in MIRROR_TILT:
		if event.is_action(action):
			return true
	return false


## Whether [param event] presses the park button.
static func park_pressed(event: InputEvent) -> bool:
	return event.is_action_pressed(PARK)


## The lever position, by letter, a wheel's gear shifter has moved to since the last physics step
## ([method WheelInput.shifter_change]); empty when it has not moved.
static func shifter_select() -> String:
	return wheel.shifter_change()


## Whether [param event] is the gamepad's shift_down, or a wheel's down paddle
## ([method WheelInput.paddle]), which parks when held ([constant PARK_HOLD]) and so moves the
## lever only when let go sooner.
static func is_pad_shift_down(event: InputEvent) -> bool:
	return event is InputEventJoypadButton \
		and (event.is_action(SHIFT_DOWN) or wheel.paddle(event) == -1)


## The gear change [param event] asks for: +1 up, -1 down, 0 none. A wheel's up paddle shifts up.
static func shift_pressed(event: InputEvent) -> int:
	if event.is_pressed() and not event.is_echo() and wheel.paddle(event) == 1:
		return 1
	if event.is_action_pressed(SHIFT_UP):
		return 1
	if event.is_action_pressed(SHIFT_DOWN):
		return -1
	return 0
